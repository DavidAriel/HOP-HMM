
function [bestTheta, bestLikelihood] = EMJ(X, params, pcPWMp, initTheta, maxIter)
    % X - N x L emission variables
    % m - amount of possible states (y)
    % n - amount of possible emissions (x)
    % maxIter - maximal iterations allowed
    % tEpsilon - probability to switch states will not exceed this number (if tEpsilon = 0.01,
    %            and m = 3 then the probability to stay in a state will not be less than 0.98)
    % pcPWMp - N x k x L
    % order - the HMM order of the E matrix
    % initial estimation parameters
    [N, L] = size(X);
    LIKELIHOOD_THRESHOLD = 10 ^ -4;
    bestLikelihood = -Inf;
    repeat = 1;
    % N x L - order + 1
    indices = reshape(matUtils.getIndices1D(X, params.order, params.n), [L-params.order+1, N]).';
    % N x L - order + 1 x maxEIndex
    indicesHotMap = matUtils.mat23Dmat(indices, params.n ^ params.order);
    % N x L  x maxEIndex
    indicesHotMap = cat(2, false(N, params.order-1, params.n ^ params.order), indicesHotMap);
    theta = initTheta;
    iterLike = [];
    for it = 1:maxIter;
        tic
        % alphaBase - N x m x L
        % alphaSub - N x m x L+J x k
        % N x m x L
        fprintf('Calculating alpha...\n')
        alpha = BaumWelchPWM.EM.forwardAlgJ(X, theta, params, pcPWMp);
        fprintf('Calculating beta...\n')
        beta = BaumWelchPWM.EM.backwardAlgJ(X, theta, params, pcPWMp);
        % N x 1
        pX = BaumWelchPWM.EM.makePx(alpha, beta);
        fprintf('Calculating Xi...\n')
        % xi - N x m x m x L
        xi = BaumWelchPWM.EM.makeXi(theta, params, alpha, beta, X, pX);
        fprintf('Calculating Gamma...\n')
        % gamma - N x m x L
        gamma = BaumWelchPWM.EM.makeGamma(params, alpha, beta, pX);
        fprintf('Update G\n');
        theta.G = updateG(alpha, beta, X, params, theta, pcPWMp);
        fprintf('Update E\n');
        theta.E = updateE(gamma, params, indicesHotMap);
        fprintf('Update T\n');
        theta.T = updateT(xi, gamma, params);

        fprintf('Update startT\n');
        theta.startT = updateStartT(gamma);
        iterLike(end+1) = matUtils.logMatSum(pX, 1);
        % DRAW
        drawStatus(theta, params, alpha, beta, gamma, pX, xi);
        assert(not(any(isnan(theta.T(:)))))
        assert(not(any(isnan(theta.E(:)))))
        assert(not(any(isnan(theta.G(:)))))
        assert(not(any(isnan(theta.F(:)))))
        assert(not(any(isnan(alpha(:)))))
        assert(not(any(isnan(beta(:)))))


        fprintf('Likelihood in iteration %d is %.2f (%.2f seconds)\n', length(iterLike), iterLike(end), toc());
        if length(iterLike) > 1 && abs((iterLike(end) - iterLike(end-1)) / iterLike(end)) < LIKELIHOOD_THRESHOLD
            fprintf('Converged\n');
            break
        end

        if bestLikelihood < iterLike(end)
            bestLikelihood = iterLike(end);
            bestTheta = theta;
            bestTheta.gamma = gamma;
        end
    end % end of iterations loop
end



% psi - N x m x k x L
% pX - N x 1
% gamma - N x m x L
function drawStatus(theta, params, alpha, beta, gamma, pX, xi)
    figure
    YsEst = mean(gamma, 3);
    YsEst = YsEst(:, 1);
    subplot(2,2,1); scatter(1:size(pX, 1), YsEst); colorbar;
    title('gamma')
    % [~, YsEst] = max(alpha, [], 2);
    % subplot(2,3,2);imagesc(permute(YsEst, [1,3,2])); colorbar;
    % % title('alpha')
    % [~, YsEst] = max(beta(:,:,1:end), [], 2);
    % subplot(2,3,3);imagesc(permute(YsEst, [1,3,2])); colorbar;
    % title('beta')
    subplot(2,2,1);plot(theta.E(:));
    title('E')
    subplot(2,2,2);
    hold on;
    plot(permute(alpha(1,1,:), [3,2,1]));
    % plot(permute(alpha(2,1,:), [3,2,1]));
    % plot(permute(alpha(3,1,:), [3,2,1]));
    % plot(permute(alpha(4,1,:), [3,2,1]));
    plot(permute(beta(1,1,:), [3,2,1]));
    % plot(permute(beta(2,1,:), [3,2,1]));
    % plot(permute(beta(3,1,:), [3,2,1]));
    % plot(permute(beta(4,1,:), [3,2,1]));
    title('alpha vs beta')
    subplot(2,2,3);plot(pX);
    title('px')
    subplot(2,2,4);plot(theta.G(:));
    title('G')
    drawnow
end

% indicesHotMap - N x L x maxEIndex
% gamma - N x m x L
% E - m x 4 x 4 x 4 x ... x 4 (order times)
function newE = updateE(gamma, params, indicesHotMap)
    %  m x N x L + J
    % m x N x L
    perGamma = permute(gamma, [2, 1, 3]);
    newE = -inf([params.m, params.n * ones(1, params.order)]);
    for i = 1:(params.n ^ params.order)
        % m x N x L -> m x 1
        newE(:, i) = matUtils.logMatSum(perGamma(:, indicesHotMap(:, :, i)), 2);
    end
    newE = matUtils.logMakeDistribution(newE);
end


% gamma - N x m x L
function newStartT = updateStartT(gamma)
    newStartT = matUtils.logMakeDistribution(matUtils.logMatSum(gamma(:, :, 1), 1))';
    % probability distribution normalization
    assert(size(newStartT, 1) > 0)
end

% xi - N x m x m x L
% gamma - N x m x L
% newT - m x m
function newT = updateT(xi, gamma, params)
    newT = permute(matUtils.logMatSum(matUtils.logMatSum(xi, 1), 4), [2, 3, 1]);
    newT = newT - repmat(matUtils.logMatSum(matUtils.logMatSum(gamma, 1), 3), [params.m,1]).';
    newT = matUtils.logMakeDistribution(newT);
    newT = log(Tbound(params, exp(newT)));
end

% X - N x L
% pcPWMp - N x k x L
% alpha - N x m x L
% beta - N x m x L
function newG = updateG(alpha, beta, X, params, theta, pcPWMp)
    [N, L] = size(X);
    kronMN = kron(1:params.m, ones(1, N));
    matSize = [params.m , params.n * ones(1, params.order)];
    beta = cat(3, beta, -inf(N, params.m, params.J + 1));
    newG = -inf(1, params.m, params.k);
    % N x m x L
    Eps = BaumWelchPWM.EM.getEp3d(theta, params, X, 1:L, kronMN, matSize);
    % aa = zeros(N, L-params.J-1, params.k);
    for t = 1:L-params.J-1
        % Ep = Eps(:, :, t);
        % N x m
        mask = log(eps * ones(N, params.m));
        mask(beta(:,:,t+1) < beta(:,:,t)) = 0;
        % N x m x k
        newPsi = zeros(N, params.m, params.k);
        newPsi = newPsi + repmat(alpha(:,:,t), [1, 1, params.k]);
        newPsi = newPsi + repmat(theta.F', [N, 1, params.k]);
        newPsi = newPsi + repmat(permute(theta.G, [3, 1, 2]), [N, 1, 1]);
        for l = 1:params.k
            newPsi(:, :, l) = newPsi(:, :, l) + beta(:, :, t+theta.lengths(l)+1);
            % N x m x k
            newPsi(:, :, l) = newPsi(:, :, l) + repmat(pcPWMp(:, l, t+1), [1, params.m]);
            newPsi(:, :, l) = newPsi(:, :, l) + Eps(:, :, t+theta.lengths(l)+1);
            newPsi(:, :, l) = newPsi(:, :, l) + mask;
            % newPsi(:, :, l) = newPsi(:, :, l) - sum(Eps(:, :, t+1:t+theta.lengths(l)), 3);

        end
        % aa(:, t, :) = newPsi(:, 1, :);
        newG = matUtils.logAdd(newG, matUtils.logMatSum(newPsi, 1));
    end
    keyboard
    figure
    aa = permute(aa, [3,2,1]);
    imagesc(aa(:,:)); colorbar;

    newG = permute(newG, [2,3,1]);
    newG = matUtils.logMakeDistribution(newG);
end

% newT - m x m
% T - m x m
function newT = Tbound(params, T)
    for i = 1 : params.m
        if T(i, i) < 1-params.tEpsilon;
            T(i, :) = T(i, :) * (params.tEpsilon / (1-T(i, i)));
            T(i, i) = 1-params.tEpsilon;
        end
    end
    newT = T;
end
