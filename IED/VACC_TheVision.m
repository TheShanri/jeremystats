function VACC_TheVision(dataDir, varargin)
% -------------------------------------------------------------------------
% VACC_TheVision — Simple event visualizer for VACC IEDs
%
% Loads all (even-numbered by default) CSC files in the folder,
% reads ets.mat / ech.mat (event start-end samples, channel participation),
% and plots ±50 ms around each event.
%
% One figure per event. Channels plotted top-to-bottom.
%
% Example:
%   VACC_TheVision("D:\PTEN\M13_pten\HF4s\IED DATA");
%
% Optional arguments:
%   'halfWidthMs'   - window half-width in seconds (default 0.05 s = ±50 ms)
%   'scaleToMicroV' - scale factor to convert A/D units → µV (default 1)
%   'minCh'         - minimum participating channels (default 6)
%   'maxCh'         - maximum participating channels (default 8)
%   'evenOnly'      - only use even-numbered CSCs (default true)
% -------------------------------------------------------------------------

%% === Parse inputs ===
p = inputParser;
p.addRequired('dataDir', @(s)ischar(s) || isstring(s));
p.addParameter('halfWidthMs', 0.05, @(x)isfinite(x) && x>0);
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x) && x>0);
p.addParameter('minCh', 6, @(x)isfinite(x) && x>=0);
p.addParameter('maxCh', 8, @(x)isfinite(x) && x>=0);
p.addParameter('evenOnly', true, @(x)islogical(x));
p.parse(dataDir, varargin{:});

dataDir       = string(p.Results.dataDir);
halfWidthSec  = p.Results.halfWidthMs;
scaleFactor   = p.Results.scaleToMicroV;
minCh         = p.Results.minCh;
maxCh         = p.Results.maxCh;
evenOnly      = p.Results.evenOnly;

samplingRate  = 30000; % Hz
halfWidthSamples = round(halfWidthSec * samplingRate);

fprintf('\n=== VACC_TheVision ===\n');

%% === Load event info ===
load(fullfile(dataDir,'ets.mat'),'ets');
load(fullfile(dataDir,'ech.mat'),'ech');

nEvents  = size(ets,1);
nEchCols = size(ech,2);
fprintf('Loaded %d events × %d channels from ets/ech\n', nEvents, nEchCols);

%% === Identify usable CSC files ===
files = dir(fullfile(dataDir, 'CSC*.ncs'));
if isempty(files)
    error('No CSC*.ncs files found in: %s', dataDir);
end

% extract channel numbers
nums = cellfun(@(n) sscanf(n,'CSC%d.ncs'), {files.name});
valid = ~isnan(nums);
if evenOnly
    valid = valid & mod(nums,2)==0;
end
files = files(valid);
nums  = nums(valid);

% sort ascending by channel number
[nums, order] = sort(nums);
files = files(order);
nChannels = numel(files);
fprintf('Using %d %s-numbered channels\n', nChannels, tern(evenOnly,'even','all'));

%% === Load all CSC data ===
fprintf('Loading CSC data (may take a while)...\n');
data = cell(1,nChannels);

for i = 1:nChannels
    fname = fullfile(dataDir, files(i).name);
    try
        samples = Nlx2MatCSC(fname, [0 0 0 0 1], 0, 1, []);  % load all samples
        samples = reshape(samples, 1, []);                   % flatten [1 x N]
        samples = single(-samples) * scaleFactor;            % invert & scale
        data{i} = samples;
    catch ME
        fprintf('  !! Failed to load %s: %s\n', files(i).name, ME.message);
        data{i} = [];
    end
end

maxLen = max(cellfun(@numel, data));
fprintf('Longest channel length: %.2f sec\n', maxLen/samplingRate);

% stack into rectangular matrix
D = zeros(nChannels, maxLen, 'single');
for i = 1:nChannels
    if isempty(data{i}), continue; end
    n = numel(data{i});
    D(i,1:n) = data{i};
end
clear data

%% === Event selection ===
chanCount = sum(ech(:,1:nChannels),2);
sel = (chanCount >= minCh) & (chanCount <= maxCh);
evtIdx = find(sel);
fprintf('Selected %d events (between %d–%d channels)\n', numel(evtIdx), minCh, maxCh);

if isempty(evtIdx)
    fprintf('No events to display.\n');
    return;
end

%% === Setup output folder ===
outDir = fullfile(dataDir, 'VACC_TheVision_out');
if ~exist(outDir,'dir'), mkdir(outDir); end

%% === Plot each selected event ===
tRel = (-halfWidthSamples:halfWidthSamples) / samplingRate * 1e3;  % in ms

for ei = 1:numel(evtIdx)
    e = evtIdx(ei);
    activeCh = logical(ech(e,1:nChannels));
    nActive   = sum(activeCh);

    % compute anchor sample (midpoint between start/end)
    anchor = round(mean(ets(e,:)));

    % define window
    s0 = anchor - halfWidthSamples;
    s1 = anchor + halfWidthSamples;

    % clip to valid range
    if s0 < 1 || s1 > size(D,2)
        fprintf('Evt %d skipped (window [%d %d] out of bounds)\n', e, s0, s1);
        continue;
    end

    % extract window data
    Y = D(:, s0:s1);
    if isempty(Y), continue; end

    % scale limits for plotting
    maxAmp = max(abs(Y(:)));
    if maxAmp == 0 || ~isfinite(maxAmp), maxAmp = 1; end
    yL = 1.05 * maxAmp * [-1 1];

    % --------- Plot ----------
    figHeight = min(150 + 90*nChannels, 5000);
    f = figure('Color','w','Position',[100 100 900 figHeight],'Visible','off');
    tl = tiledlayout(f, nChannels, 1, 'Padding','compact', 'TileSpacing','compact');

    for ch = 1:nChannels
        nexttile(tl);
        hold on; box on; grid on;

        isAct = activeCh(ch);
        if isAct
            lw = 1.4; col = [0 0 0];
        else
            lw = 0.7; col = [0.6 0.6 0.6];
        end

        plot(tRel, Y(ch,:), 'Color', col, 'LineWidth', lw);
        xline(0,'--k'); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);

        title(sprintf('CSC%d%s', nums(ch), tern(isAct,' *','')), 'FontSize',8);
        if ch==nChannels, xlabel('ms'); end
        ylabel('\muV');
    end

    sgtitle(tl, sprintf('Event %03d | %d active ch | ±%.0f ms | yLim ±%.1f µV',...
        e, nActive, halfWidthSec*1e3, yL(2)), 'FontSize',12,'FontWeight','bold');

    outFile = fullfile(outDir, sprintf('Evt%03d_%dch.png', e, nActive));
    exportgraphics(f, outFile, 'Resolution', 220);
    close(f);

    fprintf('Saved: %s\n', outFile);
end

fprintf('\nAll done! Output in: %s\n', outDir);
end

% -------------------------------------------------------------------------
function s = tern(cond, a, b)
if cond, s = a; else, s = b; end
end
