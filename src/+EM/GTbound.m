
% G - m x k
% T - m x m
function [G, T] = GTbound(params, G, T)
    if params.m == 1
        return;
    end
    G = exp(G);
    T = exp(T);
    % TODO: most of these bounding are probably not necessary, and could be removed
    [G, T] = balanceGTweights(params, G,T);
    T = limitTDiag(params, T);
    G = log(G);
    T = log(T);
end

% T - m x m
function T = limitTDiag(params, T)
    for i = 1 : params.m - 1
        T = transferWeight(params, T, i, params.m, params.PEnhancerToBackground);
        for j = 1 : params.m - 1
            T = transferWeight(params, T, i, j, params.PCrossEnhancers);
        end
    end
    for j = 1 : params.m - 1
        T = transferWeight(params, T, params.m, j, params.PBackgroundToEnhancer);
    end
end

% T - m x m
function T = transferWeight(params, T, i, j, threshold)
    if isExceedThreshold(params, threshold, T(i, j)) & i ~= j
        T(i, i) = T(i, i) + T(i, j) - threshold;
        T(i, j) = threshold;
    end
end

% G - m x k
% T - m x m
function [G, T] = balanceGTweights(params, G, T)
    PTotalBaseToSub = misc.ratio2TransitionProb(mean(params.lengths, 2), params.enhancerMotifsRatio);
    for i = 1:params.m-1
        if isExceedThreshold(params, params.PTotalBaseToSub, sum(G(i, :), 2))
            G(i, :) = G(i, :) .* (params.PTotalBaseToSub / sum(G(i, :), 2));
            T(i, :) = T(i, :) .* ((1-params.PTotalBaseToSub) / (sum(T(i, :), 2) + eps));
        end
    end
    G(params.m, :) = G(params.m, :) .* ((params.k*eps) / sum(G(params.m, :), 2));
    T(params.m, :) = T(params.m, :) .* ((1-(params.k*eps)) / (sum(T(params.m, :), 2) + eps));
end

function res = isExceedThreshold(params, thresh, val)
    res = abs(val - thresh) > thresh * params.maxPRatio;
end