function [theta] = genTheta(params, startTUniform)
    % normalized random probabilities
    if startTUniform || params.backgroundAmount == 0
        theta.startT = log(ones(params.m, 1) ./ params.m);
    else
        theta.startT = log([ones(params.m - params.backgroundAmount, 1) * params.EPS; ones(params.backgroundAmount, 1) * (1 - params.EPS * (params.m - params.backgroundAmount)) / params.backgroundAmount]);
    end
    % theta.T = log((rand(params.m) .* (params.maxT - params.minT)) + params.minT);
    % theta.G = log((rand(params.m, params.k) .* (params.maxG - params.minG)) + params.minG);
    % T = normrnd((params.maxT + params.minT) / 2, (params.maxT - params.minT) / 3);
    % G = normrnd((params.maxG + params.minG) / 2, (params.maxG - params.minG) / 3);
    s = sum(params.minT, 2) + sum(params.minG, 2);
    Ta = (params.maxT - params.minT) .* rand(params.m, params.m);
    Ga = (params.maxG - params.minG) .* rand(params.m, params.k);
    Ga = (params.maxEnhMotif .* (Ga + params.minG) ./ repmat(sum(Ga + params.minG, 2), [1, params.k])) - params.minG;
    Ta = (1 - s) .* Ta ./ repmat((sum(Ta, 2) + sum(Ga, 2)), [1, params.m]);
    Ga = (1 - s) .* Ga ./ repmat((sum(Ta, 2) + sum(Ga, 2)), [1, params.k]);
    theta.T = log(params.minT + Ta);
    theta.G = log(params.minG + Ga);

    % m x n
    theta.E = rand([params.m, ones(1, params.order) .* params.n]);
    theta.E = log(bsxfun(@times, theta.E, 1 ./ sum(theta.E, params.order+1)));

    PRETRAINED_THETA_PATH = '../data/precomputation/pretrainedTheta.mat';
    if exist(PRETRAINED_THETA_PATH, 'file') == 2
        fprintf('Found pretrained theta file: %s\n', PRETRAINED_THETA_PATH);
        load(PRETRAINED_THETA_PATH);
        [foundM, foundK] = size(G);
        foundOrder = ndims(E) - 1;
        if params.m == foundM + 1 & params.k == foundK  & foundOrder == params.order
            fprintf('Loading pretrained theta...\n');
            theta.E(1:foundM, :) = E(1:foundM, :);
            theta.G(1:foundM, 1:foundK) = G;
        end
    else
        fprintf('Using random theta initialization...\n');
    end

    assert(not(any(isnan(theta.T(:)))));
    assert(not(any(isnan(theta.E(:)))));
    assert(not(any(isnan(theta.G(:)))));
    assert(isreal(theta.T));
    assert(isreal(theta.E));
    assert(isreal(theta.G));
end