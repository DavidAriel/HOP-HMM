%merges this weird mats to one mat file that has struct array without
% overlapping sequences, since they were all joint together and the
% overlaps vectors became from one hot to a heat map of the height of
% the peak in each tissue

% peaks.mergePeakFiles()

function mergedPeaks = mergePeakFiles()
    [totalpeaks] = genTotalPeaks();
    mergedPeaks = genMergePeaks(totalpeaks);
    save('-v7.3', 'data/peaks/raw/roadmap/merged/mergedPeaks.mat', 'mergedPeaks');
end

function [totalpeaks] = genTotalPeaks()
    totalpeaks = [];
    peaksBasePath = 'data/peaks/raw/roadmap/mat';
    peakFiles = dir(fullfile(peaksBasePath, '*.peaks.mat'));
    for i = 1:length(peakFiles)
        peakFiles(i).name
        peaks = load(fullfile(peaksBasePath, peakFiles(i).name));
        S = [peaks.S{:}];
        for j=1:size(S, 2)
            S(j).overlap(i) = S(j).height;
            S(j).overlap(S(j).overlap == 1) = -inf;
        end
        totalpeaks = [totalpeaks, S];
    end
end

function mergedPeaks  = genMergePeaks(totalpeaks)

    mergedPeaks = totalpeaks;
    j = 1;
    for chrName = unique({totalpeaks.chr})
        chrMask = strcmp({totalpeaks.chr}, chrName{1});
        chrPeaks = totalpeaks(chrMask);
        [~, ind] = sort([chrPeaks.seqFrom]);
        mergedPeaks(j) = chrPeaks(ind(1));
        i = 2;
        while i <= length(ind)
            newPeak = chrPeaks(ind(i));
            oldPeak = mergedPeaks(j);
            if oldPeak.seqTo > newPeak.seqFrom
                fprintf('.')
                % oldPeak.seq'
                % newPeak.seq(end-(newPeak.seqTo-oldPeak.seqTo) + 1:end)'
                % merge
                oldPeak.seq = [oldPeak.seq, newPeak.seq(end-(newPeak.seqTo-oldPeak.seqTo) + 1:end)];
                oldPeak.seqTo = newPeak.seqTo;
                oldPeak.peakTo = max(newPeak.peakTo, oldPeak.peakTo);
                oldPeak.peakFrom = min(newPeak.peakFrom, oldPeak.peakFrom);
                % oldPeak.pos = round((oldPeak.seqFrom + newPeak.seqTo)/2) ;
                oldPeak.overlap = max(oldPeak.overlap, newPeak.overlap);
                oldPeak.height = max(oldPeak.height, newPeak.height);
                oldPeak.peakPos = mean([oldPeak.peakPos, newPeak.peakPos], 2);
                % oldPeak.min = min(oldPeak.min, newPeak.min);

                mergedPeaks(j) = oldPeak;

            else
                fprintf('O')
                j = j + 1;
                mergedPeaks(j) = newPeak;
            end
            if mod(i,100)==0
                fprintf(' %s, %d / %d\n', chrName{1}, i, length(ind));
            end
            i = i + 1;
        end
    end
    mergedPeaks = mergedPeaks(1:j);
end