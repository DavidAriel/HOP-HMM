
function [bestTheta, bestLikelihood] = EM(dataset, params, maxIter, doESharing, doGTBound, patience, repeat)
    % X - N x L emission variables
    % m - amount of possible states (y)
    % n - amount of possible emissions (x)
    % maxIter - maximal iterations allowed
    % tEpsilon - probability to switch states will not exceed this number (if tEpsilon = 0.01,
    %            and m = 3 then the probability to stay in a state will not be less than 0.98)
    % pcPWMp - N x k x L
    % order - the HMM order of the E matrix
    % initial estimation parameters

    [N, L] = size(dataset.X);
    fprintf('Starting EM algorithm on %d x %d\n', N, L);
    bestLikelihood = -Inf;
    % N x L - order + 1
    indices = reshape(matUtils.getIndices1D(dataset.X, params.order, params.n), [L-params.order+1, N]).';
    % N x L - order + 1 x maxEIndex
    indicesHotMap = matUtils.mat23Dmat(indices, params.n ^ params.order);
    % N x L  x maxEIndex
    indicesHotMap = cat(2, false(N, params.order-1, params.n ^ params.order), indicesHotMap);
    % figure
    for rep = 1:repeat
        % X = X(randperm(N), :);
        fprintf('Repeat %d / %d\n', rep, repeat);
        initTheta = misc.genTheta(params, true);
        [iterLike, theta] = singleRunEMBatch(dataset, params, initTheta, maxIter, indicesHotMap, N, L, doESharing, doGTBound, patience);
        if bestLikelihood < iterLike(end)
            bestLikelihood = iterLike(end);
            bestTheta = theta;
        end
    end
end

% iterates the EM algorithm, returns the likelihood of the best iteration, and theta parameters at that iteration
function [iterLike, theta] = singleRunEMBatch(dataset, params, initTheta, maxIter, indicesHotMap, N, L, doESharing, doGTBound, patience)
    LIKELIHOOD_THRESHOLD = 10 ^ -5;
    theta(1) = initTheta;
    iterLikes = -inf(maxIter, 1);

    for it = 1:maxIter
        fprintf('EM iteration %d / %d\n', it, maxIter);
        tic;
        N = size(dataset.X, 1);
        batchAmount = ceil(N / params.batchSize);
        updatedTheta = theta(1);
        updatedTheta.T = updatedTheta.T * 0;
        updatedTheta.E = updatedTheta.E * 0;
        updatedTheta.G = updatedTheta.G * 0;
        updatedTheta.startT = updatedTheta.startT * 0;

        for u = 1:batchAmount
            fprintf('Batch %d / %d\n', u, batchAmount);
            % N x m x k+m x L
            batchMask = mod(1:N, batchAmount) == u - 1;
            XBatch = dataset.X(batchMask, :);
            pcPWMpBatch = dataset.pcPWMp(batchMask, :, :);
            indicesHotMapBatch = indicesHotMap(batchMask, :, :);

            % alpha - N x m x L
            % beta - N x m x L
            % pX - N x 1
            % xi - N x m x m x L
            % gamma - N x m x L
            % psi - N x m x k x L
            [alpha, beta, pX, xi, gamma, psi] = EM.EStep(params, theta(it), XBatch, pcPWMpBatch);
            % close all;
            % show.showTheta(theta);
            % show.seqSampleCertainty(params, dataset.Y, gamma, psi, 8, true);
            E = updateE(gamma, params, indicesHotMapBatch);
            % drawStatus(theta, params, alpha, beta, gamma, pX, xi, psi);
            if doESharing
                % theta.E = log(repmat(mean(exp(theta.E), 1), [params.n, ones(1, params.order)]));
                E(1:end - params.backgroundAmount, :) = repmat(log(mean(exp(E(1:end - params.backgroundAmount, :)), 1)), [params.n - params.backgroundAmount, 1]);
            end
            fprintf('. ');
            startT = updateStartT(gamma);
            [G, T] = updateGT(params, xi, gamma, psi, doGTBound);
            assert(not(any(isnan(startT(:)))));
            assert(not(any(isnan(T(:)))));
            assert(not(any(isnan(E(:)))));
            assert(not(any(isnan(G(:)))));
            assert(not(any(isnan(alpha(:)))));
            assert(not(any(isnan(beta(:)))));
            updatedTheta.T = updatedTheta.T + exp(T);
            updatedTheta.E = updatedTheta.E + exp(E);
            updatedTheta.G = updatedTheta.G + exp(G);
            updatedTheta.startT = updatedTheta.startT + exp(startT);
            iterLikes(it) = matUtils.logAdd(iterLikes(it), matUtils.logMatSum(pX, 1));
        end % end batch loop

        iterLikes(it) = iterLikes(it) - batchAmount;
        iterLike = iterLikes(it);
        theta(it + 1).T = log(updatedTheta.T / batchAmount);
        theta(it + 1).E = log(updatedTheta.E / batchAmount);
        theta(it + 1).G = log(updatedTheta.G / batchAmount);
        theta(it + 1).startT = log(updatedTheta.startT / batchAmount);
        % clf
        % show.showTwoThetas(params, dataset.theta, theta(it + 1), false, sprintf('%d', it), 'tmp.jpg');
        % drawnow;
        if doGTBound
            fprintf('Bounding G and T\n');
            [theta(it + 1).G, theta(it + 1).T] = EM.GTbound(params, theta(it + 1).G, theta(it + 1).T);
        end

        motifsPer = sum(exp(theta(it + 1).G(:)), 1).*100;
        timeLapse = toc();
        R = cov(theta(it + 1).G);
        fprintf('It %d: log-like: %.2f Time: %.2fs, motifs: ~%.2f%% cov: %.2f\n', it, iterLike, timeLapse, motifsPer, mean(R(:)));
        if it > 1 && abs((iterLike - iterLikes(it - 1)) / iterLike) < LIKELIHOOD_THRESHOLD
            fprintf('Converged\n');
            break
        end

        if it > patience && iterLike < iterLikes(it - patience)
            fprintf('Patience reached, Converged\n');
            break
        end
    end % end EM iteration loop
    [iterLike, ind] = max(iterLikes);
    theta = theta(ind);
 end


% psi - N x m x k x L
% pX - N x 1
% gamma - N x m x L
function drawStatus(theta, params, alpha, beta, gamma, pX, xi, psi)
    figure;
    YsEst = mean(gamma, 3);
    YsEst = YsEst(:, 1);
    subplot(2,2,1);
    scatter(1:size(pX, 1), YsEst); colorbar;
    title('Px');
    % [~, YsEst] = max(alpha, [], 2);
    % subplot(2,3,2);imagesc(permute(YsEst, [1,3,2])); colorbar;
    % % title('alpha')
    % [~, YsEst] = max(beta(:,:,1:end), [], 2);
    % subplot(2,3,3);imagesc(permute(YsEst, [1,3,2])); colorbar;
    % title('beta')
    subplot(2,2,2);plot(exp(theta.E(:)));
    plot(exp(theta.E(:)));
    ylim([0,1]);
    title('E');

    subplot(2,2,3);
    plot(permute(gamma(1,1,:), [3,2,1]));
    hold on;
    % N x m x k x L
    plot(permute(matUtils.logMatSum(psi(1,1,:,:), 3), [4,3,2,1]));
    title('Postirior');
    subplot(2,2,4);plot(exp(theta.G(:)));
    ylim([0,1]);
    title('G');
    drawnow;
end

% indicesHotMap - N x L x maxEIndex
% gamma - N x m x L
% E - m x 4 x 4 x 4 x ... x 4 (order times)
function newE = updateE(gamma, params, kmerIndicesHotMap)
    %  m x N x L + J
    % m x N x L
    permGamma = permute(gamma, [2, 1, 3]);
    newE = -inf([params.m, params.n * ones(1, params.order)]);
    for i = 1:(params.n ^ params.order)
        % m x N x L -> m x 1
        kmerPosteriorProb = permGamma(:, kmerIndicesHotMap(:, :, i));
        if size(kmerPosteriorProb, 2) > 0 
            newE(:, i) = matUtils.logMatSum(kmerPosteriorProb, 2);
        end
    end
    newE = matUtils.logMakeDistribution(newE);
end


% gamma - N x m x L
function newStartT = updateStartT(gamma)
    newStartT = matUtils.logMakeDistribution(matUtils.logMatSum(gamma(:, :, 1), 1))';
    % probability distribution normalization
    assert(size(newStartT, 1) > 0);
end



% alpha - N x m x L
% beta - N x m x L
% gamma - N x m x L
% xi - N x m x m x L
% psi - N x m x k x L
% newG - m x k
% newT - m x m
function [newG, newT] = updateGT(params, xi, gamma, psi, doGTBound)
    [N, ~, L] = size(gamma);

    % N x m x k+m x L
    psiXiMerged = cat(3, psi, xi);
    psiXiMerged = psiXiMerged(:, :, :, 1:end-params.J);
    % psiXiMerged = psiXiMerged - permute(repmat(gamma(:,:,1:end-params.J), [1, 1, 1, params.k+params.m]), [1,2,4,3]);

    psiXiMerged = matUtils.logMatSum(psiXiMerged, 4);
    mergedAveraged = matUtils.logMatSum(psiXiMerged, 1);
    mergedAveraged = matUtils.logMakeDistribution(mergedAveraged);
    mergedAveraged = permute(mergedAveraged, [2,3,1]);
    newG = mergedAveraged(:, 1:params.k);
    newT = mergedAveraged(:, params.k+1:end);
end
