function SolidSputterAvgStack(inputFolder, dataMatPath, varargin)
% SolidSputterAvgStack
% Build two "rows-only" stack figures of per-channel average waveforms:
% one for SOLID events and one for SPUTTER events.
%
% INPUT FOLDER LAYOUT
%   inputFolder/
%     Solid/      <-- PNGs like: Evt010_7ch_align-midpoint_HW900s_30ms_rows-only (1).png
%     Sputter/    <-- same idea
%     *.xlsx      <-- spreadsheet; row (event+1) holds [startIdx, endIdx] in first two columns
%
% RAW DATA MAT (dataMatPath) must contain:
%   d  : [nRows x nSamp] (Neuralynx-style rows=channels)
%   sfx: sampling rate (Hz)
%   kept_channels (optional): original CSC channel labels
%
% BEHAVIOR
% - Parses event numbers from PNG names.
% - For each group (Solid/Sputter), gathers events -> for each channel:
%     align to per-channel peak within [startIdx, endIdx],
%     extract ±halfWidthMs window, scale to µV, average & SEM across events.
% - Produces TWO figures (SOLID/SPUTTER), one column, N rows = #channels,
%   fixed symmetric y-limits per figure, mean line with SEM shading.
%
% NAME-VALUE OPTIONS
%   'halfWidthMs'     (double) default 30e-3     % 30 ms half-window
%   'scaleToMicroV'   (double) default 1         % multiply raw units -> µV
%   'peakPolarity'    ('abs'|'pos'|'neg') default 'abs' (peak detection within event window)
%   'excelPath'       (string) default: auto-detect *.xlsx in inputFolder
%   'saveDir'         (string) default: inputFolder   % outputs land here
%   'channelIndices'  (vector) default [] -> all rows in mf.d
%   'maxEventsPerGroup' (int) default [] -> use all; set to cap for speed
%
% OUTPUTS
%   - PNGs:
%       AvgStack_SOLID_align-peak_HW<samples>_<ms>_rows-only_uV_fixedY.png
%       AvgStack_SPUTTER_align-peak_HW<samples>_<ms>_rows-only_uV_fixedY.png
%   - MATs:
%       AvgStack_SOLID_stats.mat  (mu, se, tRelMs, usedEvents, chList, kept_channels)
%       AvgStack_SPUTTER_stats.mat
%
% EXAMPLE
%   SolidSputterAvgStack('C:\data\run01', 'C:\data\LL_input_data.mat', ...
%       'halfWidthMs',0.030, 'scaleToMicroV', 1, 'peakPolarity','abs');

% ---------- Parse args ----------
p = inputParser;
p.addRequired('inputFolder', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('peakPolarity','pos', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('excelPath',"", @(s)ischar(s)||isstring(s));
p.addParameter('saveDir',"", @(s)ischar(s)||isstring(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('maxEventsPerGroup', [], @(x) isempty(x) || (isscalar(x) && x>0));
p.parse(inputFolder, dataMatPath, varargin{:});

inputFolder     = string(p.Results.inputFolder);
dataMatPath     = string(p.Results.dataMatPath);
halfWidthMs     = p.Results.halfWidthMs;
scaleToMicroV   = p.Results.scaleToMicroV;
peakPolarity    = lower(string(p.Results.peakPolarity));
excelPath       = string(p.Results.excelPath);
saveDir         = string(p.Results.saveDir);
channelIndices  = p.Results.channelIndices;
maxEventsPerGrp = p.Results.maxEventsPerGroup;

% ---------- Locate pieces ----------
solidDir   = fullfile(inputFolder, "Solid");
sputterDir = fullfile(inputFolder, "Sputter");
assert(isfolder(solidDir),   'Missing folder: %s', solidDir);
assert(isfolder(sputterDir), 'Missing folder: %s', sputterDir);

if excelPath == ""
    xl = dir(fullfile(inputFolder, "*.xlsx"));
    assert(~isempty(xl), 'No Excel file (*.xlsx) found in %s', inputFolder);
    excelPath = fullfile(xl(1).folder, xl(1).name);
end
assert(isfile(excelPath), 'Excel not found: %s', excelPath);

assert(isfile(dataMatPath), 'Data MAT not found: %s', dataMatPath);
mf = matfile(dataMatPath);
try sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRowsAll = size(mf,'d',1);
nSamp    = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end

% Channels to process
if isempty(channelIndices)
    chList = 1:nRowsAll;
else
    chList = channelIndices(:).';
    chList = chList(chList>=1 & chList<=nRowsAll);
end
nCh = numel(chList);

% Output dir
if saveDir == "", outDir = inputFolder; else, outDir = char(saveDir); end
if ~exist(outDir,'dir'), mkdir(outDir); end

% Window
HW = max(1, round(halfWidthMs * sfx));    % half-width in samples
tRelSamples = -HW:HW;
tRelMs = (tRelSamples / sfx) * 1e3;
winN = numel(tRelSamples);

fprintf('--- SolidSputterAvgStack ---\n');
fprintf('Data: %s\n', dataMatPath);
fprintf('Excel: %s\n', excelPath);
fprintf('Solid dir: %s | Sputter dir: %s\n', solidDir, sputterDir);
fprintf('Channels: %d | Half-width: %d samples (%.2f ms) | Scale: x%g to µV\n', ...
    nCh, HW, 1e3*HW/sfx, scaleToMicroV);

% ---------- Load spreadsheet (first 2 cols: startIdx, endIdx) ----------
T = readtable(excelPath, 'ReadVariableNames', true);
if width(T) < 2
    error('Excel must have at least 2 columns: [startIdx, endIdx].');
end
startIdxCol = T{:,1};
endIdxCol   = T{:,2};
if ~isnumeric(startIdxCol) || ~isnumeric(endIdxCol)
    error('First two columns must be numeric sample indices.');
end
NrowsXL = height(T);

% ---------- Get event lists from PNGs ----------
evtSOL = unique(parseEvtNumsFromPngs(solidDir));
evtSPU = unique(parseEvtNumsFromPngs(sputterDir));
fprintf('Found %d SOLID events, %d SPUTTER events from filenames.\n', numel(evtSOL), numel(evtSPU));

if ~isempty(maxEventsPerGrp)
    evtSOL = evtSOL(1:min(end, maxEventsPerGrp));
    evtSPU = evtSPU(1:min(end, maxEventsPerGrp));
end

% ---------- Build averages ----------
[muSOL, seSOL, usedSOL] = avgForGroup(evtSOL, 'SOLID');
[muSPU, seSPU, usedSPU] = avgForGroup(evtSPU, 'SPUTTER');

% ---------- Plot stacks ----------
plotStack(muSOL, seSOL, 'SOLID');
plotStack(muSPU, seSPU, 'SPUTTER');

fprintf('Done. Outputs in: %s\n', outDir);

% ====================== Nested helpers ======================

    function evts = parseEvtNumsFromPngs(dirpath)
        L = dir(fullfile(dirpath, '*.png'));
        evts = [];
        for k = 1:numel(L)
            nm = L(k).name;
            % Match Evt<digits>
            m = regexp(nm, 'Evt(\d+)', 'tokens', 'once');
            if ~isempty(m)
                ev = str2double(m{1});
                if isfinite(ev), evts(end+1) = ev; end %#ok<AGROW>
            end
        end
    end

    function [MU, SE, usedEvents] = avgForGroup(evtList, tag)
        if isempty(evtList)
            MU = []; SE = []; usedEvents = [];
            warning('%s: no events.', tag);
            return;
        end

        MU = nan(nCh, winN);
        SE = nan(nCh, winN);
        usedEvents = [];

        % Pre-collect per-channel stacks in cell (to handle variable valid windows)
        stacks = cell(nCh,1);
        for i=1:nCh, stacks{i} = []; end

        nBad = 0;
        for ii = 1:numel(evtList)
            e = evtList(ii);
            rowXL = e + 1; % header offset
            if rowXL < 1 || rowXL > NrowsXL
                nBad = nBad+1; continue;
            end
            s0_ev = max(1, round(startIdxCol(rowXL)));
            s1_ev = min(nSamp, round(endIdxCol(rowXL)));
            if ~isfinite(s0_ev) || ~isfinite(s1_ev) || s1_ev<=s0_ev
                nBad = nBad+1; continue;
            end

            okAnyCh = false;
            for k = 1:nCh
                ch = chList(k);
                % find per-channel local peak within event window
                yseg = double(mf.d(ch, s0_ev:s1_ev));
                if any(~isfinite(yseg)), continue; end

                switch peakPolarity
                    case "pos", [~, kp] = max(yseg);
                    case "neg", [~, kp] = min(yseg);
                    otherwise,  [~, kp] = max(abs(yseg));
                end
                anchor = s0_ev + kp - 1;

                s0 = anchor - HW; s1 = anchor + HW;
                if s0 < 1 || s1 > nSamp, continue; end

                y = double(mf.d(ch, s0:s1)) * scaleToMicroV; % µV
                if any(~isfinite(y)), continue; end

                stacks{k}(end+1, :) = y; %#ok<AGROW>
                okAnyCh = true;
            end

            if okAnyCh
                usedEvents(end+1) = e; %#ok<AGROW>
            end
        end

        if nBad>0
            fprintf('%s: skipped %d event(s) due to bad/missing indices/out-of-bounds.\n', tag, nBad);
        end
        fprintf('%s: used %d/%d events.\n', tag, numel(usedEvents), numel(evtList));

        % Compute mean ± SEM per channel  ✅ FIXED
        for k = 1:nCh
            nUsedCh = size(stacks{k},1);
            if nUsedCh > 0
                MU(k,:) = mean(stacks{k}, 1, 'omitnan');
                SE(k,:) = std(stacks{k}, 0, 1, 'omitnan') ./ sqrt(nUsedCh);
            end
        end

        % Trim any all-NaN leading/trailing channels if channelIndices was custom
        % (we keep layout 1:1 with chList; NaN rows will still plot empty)
    end

    function plotStack(MU, SE, tag)
        if isempty(MU)
            warning('%s: no data to plot.', tag);
            return;
        end
        % Fixed symmetric y-limits across ALL channels, including SEM bands
        maxAbs = max(abs([MU(:); (MU(:)+SE(:)); (MU(:)-SE(:))]), [], 'omitnan');
        if ~isfinite(maxAbs) || maxAbs==0, maxAbs = 1; end
        pad = 0.05;
        span = (1+pad) * maxAbs;
        yL = span * [-1 1];

        nRowsGrid = nCh;
        nCols = 1;

        perRowPx = 90; basePx = 200; maxPx = 5000;
        figH = min(maxPx, basePx + perRowPx * nRowsGrid);
        f = figure('Color','w','Position',[60 60 900 figH],'Visible','off');
        tl = tiledlayout(f, nRowsGrid, nCols, 'Padding','compact','TileSpacing','compact');

        for k = 1:nCh
            nexttile(tl); hold on; box on; grid on;
            mu = MU(k,:); se = SE(k,:);
            if any(isfinite(mu))
                shadedMean(tRelMs, mu, se);
                xline(0,'--k','LineWidth',0.8); yline(0,':','Color',[0.7 0.7 0.7]);
                ylim(yL);
            else
                % empty channel
                ylim(yL);
            end

            ch = chList(k);
            ttl = localTitle(ch, kept_channels);
            title(ttl,'FontSize',8);

            ax = gca; ax.FontSize = 8;
            if k < nCh, ax.XTickLabel = []; else, xlabel('ms'); end
            ylabel('\muV');
        end

        sg = sprintf('%s | align: peak(%s) | Win: \\pm%.1f ms | nEvents=%d | yLim=\\pm%.1f µV', ...
            tag, peakPolarity, 1e3*HW/sfx, size(MU,2)>0 * numel(find(~all(isnan(MU),2))), (1+pad)*maxAbs);
        sgtitle(tl, sg, 'FontSize',12,'FontWeight','bold');

        outPng = fullfile(outDir, sprintf('AvgStack_%s_align-peak_HW%ds_%dms_rows-only_uV_fixedY.png', ...
            tag, HW, round(1e3*HW/sfx)));
        exportgraphics(f, outPng, 'Resolution', 220);
        close(f);

        % Save stats
        statsPath = fullfile(outDir, sprintf('AvgStack_%s_stats.mat', tag));
        usedEvents = []; %#ok<NASGU> % (populated earlier per group; optional to store)
        save(statsPath, 'MU','SE','tRelMs','chList','kept_channels','scaleToMicroV','halfWidthMs','sfx');
        fprintf('Saved: %s\n', outPng);
        fprintf('Saved: %s\n', statsPath);
    end

    function shadedMean(x, mu, se)
        if isempty(mu) || all(~isfinite(mu)), return; end
        yu = mu + se; yl = mu - se;
        xp = [x, fliplr(x)];
        yp = [yu, fliplr(yl)];
        patch('XData',xp,'YData',yp, ...
            'FaceColor',[0.3 0.3 0.9],'FaceAlpha',0.25, ...
            'EdgeColor','none','HandleVisibility','off');
        plot(x, mu, 'LineWidth', 1.8);
    end

    function ttl = localTitle(rowIdx, kept)
        if ~isempty(kept)
            ttl = sprintf('row %d (CSC%d)', rowIdx, kept(rowIdx));
        else
            ttl = sprintf('row %d', rowIdx);
        end
    end

end
