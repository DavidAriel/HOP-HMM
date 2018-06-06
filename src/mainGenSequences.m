
% mainGenSequences(300, 10000, 5, 25, true);
% mainGenSequences(10000, 500, 5, 25, false);
function mergedPeaksMin = mainGenSequences(N, L, m, k, mixed)
    dbstop if error
    clear pcPWMp
    close all;

    delete(fullfile('..', 'data', 'precomputation', 'pcPWMp.mat'));
    params = misc.genParams(m, k);
    params.m = m;
    theta = genHumanTheta(params, mixed);
    show.showTheta(theta);
    [seqs, Y] = misc.genSequences(theta, params, N, L);
    Y2 = Y(:,:,2);
    Y = Y(:,:,1);
    overlaps = matUtils.vec2mat(Y(:, 1)', params.m)';
    lengths = ones(N, 1) * L;
    tissueNames = num2cell(num2str([1:params.m]'));
    save(fullfile('..', 'data', 'peaks', 'mergedPeaksMinimized_fake.mat'), 'seqs', 'lengths', 'overlaps', 'theta', 'Y', 'Y2', 'theta', 'tissueNames');
    mergedPeaksMin.seqs = seqs;
    mergedPeaksMin.overlaps = overlaps;
    mergedPeaksMin.lengths = lengths;
    mergedPeaksMin.theta = theta;
    mergedPeaksMin.Y = Y
    mergedPeaksMin.Y2 = Y2;
    imagesc(Y+Y2)
end






function T = genHumanT(params, mixed)
    % T = ones(params.m) * params.PCrossEnhancers;
    % T(eye(params.m) == 1) = 1 - (params.PCrossEnhancers * (params.m-2) + params.PEnhancerToBackground + params.PTotalBaseToSub);
    % T(:, end) = params.PEnhancerToBackground;
    % T(end, :) = params.PBackgroundToEnhancer;
    % T(end, end) = 1 - params.PBackgroundToEnhancer * (params.m-1);
    T = (params.minT + params.maxT) ./ 2;
    if not(mixed)
        T(not(eye(params.m))) = eps;
    end
    T = log(T);
end

function G = genHumanG(params)
    BACKGROUND_G_NOISE = 0.001;
    NUM_OF_NONZEROS = 1;
    G = zeros(params.m, params.k);
    for i = 1:params.m
        % G(i, :) = mod(1:params.k, params.m) == (i-1);
        G(i, :) = eps;
        % G(i, datasample(1:params.k, NUM_OF_NONZEROS)) = 1;
        G(i, i) = 1;
    end
    G = G + (rand(params.m, params.k) .* BACKGROUND_G_NOISE);
    G = G ./ repmat(sum(G, 2), [1, params.k]);
    G = G .* params.PTotalBaseToSub;
    G(end, :) = eps;
    G(:, 1:10)
    G = log(G);
end

function startT = genHumanStartT(params, mixed)
    if mixed
        startT = log([ones(params.m-1, 1)*eps; 1-(params.m-1)*eps]);
    else
        startT = log(ones(params.m, 1) ./ params.m);
    end
end

function E = genHumanE(params)
    E = zeros([params.m, params.n * ones(1,params.order)]);
    for i=1:params.m
        E(i, :) = [ 9298, 6036, 7032, 4862, 7625, 7735, 6107, 6381, 8470,...
                          1103, 7053, 6677, 4151, 4202, 3203, 4895, 4996, 6551,...
                          4387, 3150, 4592, 7331, 5951, 6900, 6870, 1289, 5710,...
                          6244, 4139, 7391, 4423, 6990, 7396, 9784, 7709, 4184,...
                          1317, 1586, 1363, 1117, 8430, 1545, 7243, 7822, 5593,...
                          9804, 6587, 6132, 5651, 5732, 4213, 3952, 5459, 8393,...
                          7066, 8345, 5533, 1235, 4689, 7744, 5493, 7510, 4973,...
                          9313]';
        % E(i, :) = E(i, :) + (rand(1, params.n ^ params.order) * 3000);
    end
    E = log(bsxfun(@times, E, 1./sum(E, ndims(E))));
end


function theta = genHumanTheta(params, mixed)
    theta.E = genHumanE(params);
    theta.T = genHumanT(params, mixed);
    theta.G = genHumanG(params);
    T = exp(theta.T);
    G = exp(theta.G);

    s = sum(T, 2) + sum(G, 2);
    theta.T = log(T ./ repmat(s, [1, params.m]));
    theta.G = log(G ./ repmat(s, [1, params.k]));
    theta.startT = genHumanStartT(params, mixed);
end
