
function [bestTheta, likelihood] = EMJ(Xs, params, pcPWMp, maxIter)
    % PWMs - k x n x J emission matrix of m Jaspar PWMs with length J
    %        true length of i'th PWM< J and given in lengths(i) if a PWM is
    %        shorter than j, it is aligned to the end of the 3rd dimension.
    % Xs - N x L emission variables
    % m - amount of possible states (y)
    % n - amount of possible emissions (x)
    % maxIter - maximal iterations allowed
    % tEpsilon - probability to switch states will not exceed this number (if tEpsilon = 0.01,
    %            and m = 3 then the probability to stay in a state will not be less than 0.98)
    % order - the HMM order of the E matrix
    % initial estimation parameters

    LIKELIHOOD_THRESHOLD = 10 ^ -4;
    bestLikelihood = -Inf;
    repeat = 1;

    % N x L -order + 1
    indices = reshape(matUtils.getIndices1D(Xs, params.order), [params.L-params.order+1, params.N]).';
    % N x L -order + 1 x maxEIndex
    indicesHotMap = matUtils.mat23Dmat(indices, params.n ^ params.order);
    % N x L  x maxEIndex
    indicesHotMap = cat(2, false(params.N, params.order-1+params.J, params.n ^ params.order), indicesHotMap);
    for rep = 1:repeat
        theta = BaumWelchPWM.genThetaJ(params);

        iterLike = [];
        for it = 1:maxIter;
            % N x m x L
            % N x L
            [alpha, scale] = BaumWelchPWM.forwardAlgJ(Xs, theta, params, pcPWMp);
            % N x m x L
            beta = BaumWelchPWM.backwardAlgJ(Xs, theta, params, scale, pcPWMp);
            alpha = cat(3, alpha, zeros(params.N, params.m, params.J));
            beta = cat(3, beta, zeros(params.N, params.m, params.J));


            theta = updateTheta(theta, params, Xs, indicesHotMap, pcPWMp, alpha, beta);
            iterLike(end + 1) = sum(log(scale(:)));
            fprintf('Likelihood in iteration %d is %.2f\n', length(iterLike), iterLike(end));
            if length(iterLike) > 1 && abs((iterLike(end) - iterLike(end-1)) / iterLike(end)) < LIKELIHOOD_THRESHOLD
                fprintf('Converged\n');
                break
            end

            if bestLikelihood < iterLike(end)
                bestLikelihood = iterLike(end);
                bestTheta = theta;
            end
        end % end of iterations loop
    end % end of repeat loop

    % return parameters with best likelihood
    likelihood = bestLikelihood;
end

function theta = updateTheta(theta, params, Xs, indicesHotMap, pcPWMp, alpha, beta)
    fprintf('Updating theta\n');
    % N x m x L + J
    % gamma_t(i) = P(y_t = i|x_1:L)
    gamma = alpha .* beta ./ (repmat(sum(alpha .* beta, 2), [1, params.m, 1]) + eps);
    [theta.T, theta.M, theta.F] = updateTMF(theta, params, Xs, alpha, beta, pcPWMp);
    theta.E = updateE(gamma, theta, params, indicesHotMap);
    theta.startT = updateStartT(gamma, theta);
    % T bound trick
    theta.T = Tbound(theta, params);
end

% indicesHotMap - N x L x maxEIndex
% gamma - N x m x L + J
% E - m x 4 x 4 x 4 x ... x 4 (order times)
function newE = updateE(gamma, theta, params, indicesHotMap)
    %  m x N x L + J
    fprintf('Update E\n');
    perGamma = permute(gamma, [2, 1, 3]);
    for i = 1: (params.n ^ params.order)
        % m x N x L -> m x 1
        theta.E(:, i) = theta.E(:, i) + sum(perGamma(:, indicesHotMap(:, :, i)), 2);
    end

    newE = bsxfun(@times, theta.E, 1 ./ sum(theta.E, params.order+1));
end

% gamma - N x m x L + J
function newStartT = updateStartT(gamma, theta)
    theta.startT = theta.startT + mean(gamma(:, :, 1), 1).';
    % probability distribution normalization
    newStartT = theta.startT / sum(theta.startT);
end

% M - m x k
% F - k x 1
% T - m x m
% E - m x 4 x 4 x 4 x ... x 4 (order times)
% alpha - N x m x L + J
% beta - N x m x L + J
% lengths - k x 1
function [newT, newM, newF] = updateTMF(theta, params, Xs, alpha, beta, pcPWMp)

    TCorrection = zeros(params.m, params.m);
    MCorrection = zeros(params.m, params.k);
    FCorrection = zeros(params.m, 2);
    % todo: remove slow loop
    matSize = [params.m , 4 * ones(1, params.order)];
    kronMN = kron(1:params.m, ones(1, params.N));

    Ms = repmat(permute(theta.M, [3, 1, 2]), [params.N, 1, 1]);
    for t = 2 : params.L
        fprintf('\rUpdate TMF %.2f%%', 100*t/params.L);
        % for each letter in seqs we get more information about the transition matrix update
        % N x k
        PWMProb = pcPWMp(:, :, t);
        % N x m x k
        R = repmat(alpha(:, :, t-1), [1,1,params.k]) .* beta(:, :, t + theta.lengths - 1);
        R = R .* repmat(permute(PWMProb, [1,3,2]), [1,params.m,1]);
        R = R .* Ms;
        assert(not(any(isnan(R(:)))))
        % m x k x N -> m x k
        % N x m
        Ep = BaumWelchPWM.getEp(theta, params, Xs, t, kronMN, matSize);
        % (m x N * N x m) .* (m x m)
        TCorrectiont = (alpha(:, :, t - 1)' * (beta(:, :, t) .* Ep)) .* theta.T;
        TCorrection = TCorrection + (TCorrectiont / sum(sum(TCorrectiont)) + eps);


        % N x m x k
        MCorrectiont = shiftdim(sum(R, 1), 1);
        MCorrection = MCorrection + (MCorrectiont / (sum(MCorrectiont(:)) + eps));

        FCorrectiont = [matUtils.sumDim(R, [1, 3]), sum(TCorrectiont, 2)];
        FCorrection = FCorrection + FCorrectiont;
    end
    fprintf('\n');
    newT = theta.T + TCorrection;
    newT = bsxfun(@times, newT, 1 ./ sum(newT, 2));
    newM = theta.M + MCorrection;
    newM = bsxfun(@times, newM, 1 ./ sum(newM, 2));
    newF = [theta.F, 1-theta.F] + FCorrection;
    newF = bsxfun(@times, newF, 1 ./ sum(newF, 2));
    newF = newF(:, 1);
end

function newT = Tbound(theta, params)
    for i = 1 : params.m
        for j = 1 : params.m
            if i ~= j && theta.T(i,j) > params.tEpsilon
                theta.T(i, i) = theta.T(i, i) + (theta.T(i, j) - params.tEpsilon);
                theta.T(i, j) = params.tEpsilon;
            end
        end
    end
    newT = theta.T;
end

