function VACC_TheVision(dataDir, varargin)
% VACC_TheVision — full-load visualizer for IED events (VACC edition)
% Loads all even-numbered CSC*.ncs files from the folder once,
% loads ets.mat / ech.mat, and plots ±50 ms windows per event.
%
% Usage:
%   VACC_TheVision("D:\PTEN\M13_pten\HF4s\IED DATA");
%
% Optional Name–Value pairs:
%   'halfWidthMs'   default 50e-3
%   'scaleToMicroV' default 1
%   'minCh'         default 6
%   'maxCh'         default 8
%   'evenOnly'      default true

% ---------- Parse ----------
p = inputParser;
p.addRequired('dataDir', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 50e-3, @(x)isfinite(x)&&x>0);
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('minCh', 6, @(x)isfinite(x)&&x>=0);
p.addParameter('maxCh', 8, @(x)isfinite(x)&&x>=0);
p.addParameter('evenOnly', true, @(x)islogical(x));
p.parse(dataDir, varargin{:});
dataDir = string(p.Results.dataDir);
HWms = p.Results.halfWidthMs;
scaleToMicroV = p.Results.scaleToMicroV;
minCh = p.Results.minCh;
maxCh = p.Results.maxCh;
evenOnly = p.Results.evenOnly;

% ---------- Load ets / ech ----------
etsFile = fullfile(dataDir, "ets.mat");
echFile = fullfile(dataDir, "ech.mat");
if ~isfile(etsFile) || ~isfile(echFile)
    error("ets.mat or ech.mat not found in %s", dataDir);
end
load(etsFile, "ets");
load(echFile, "ech");
fprintf("Loaded %d events × %d channels from ets/ech\n", size(ets,1), size(ech,2));

% ---------- Find CSC files ----------
files = dir(fullfile(dataDir, 'CSC*.ncs'));
if isempty(files), error('No CSC*.ncs found in %s', dataDir); end

% Extract numeric channel numbers and keep evens if requested
nums = cellfun(@(n) sscanf(n,'CSC%d.ncs'), {files.name});
keep = ~isnan(nums);
if evenOnly
    keep = keep & mod(nums,2)==0;
end
files = files(keep);
nums  = nums(keep);
[nums, order] = sort(nums);
files = files(order);
nCh = numel(files);
fprintf('Using %d %s-numbered channels\n', nCh, tern(evenOnly,'even','all'));

% ---------- Load all CSC data ----------
fprintf('Loading all channel data into memory...\n');
S = cell(1,nCh);
for k = 1:nCh
    fn = fullfile(dataDir, files(k).name);
    try
        samples = Nlx2MatCSC(fn, [0 0 0 0 1], 0, 1, []); % read all
        s = reshape(samples, 1, []);          % flatten
        s = single(-s) * scaleToMicroV;       % invert polarity, scale
        S{k} = s;
    catch ME
        fprintf('Ch%d failed to load (%s)\n', nums(k), ME.message);
        S{k} = [];
    end
end
maxlen = max(cellfun(@numel, S));
d = zeros(nCh, maxlen, 'single');
for k = 1:nCh
    if isempty(S{k}), continue; end
    v = S{k};
    d(k,1:numel(v)) = v;
end
clear S
fprintf('Loaded %d channels, %d samples each (approx).\n', nCh, maxlen);

% ---------- Parameters ----------
sfx = 30000;                              % sampling rate
HW = round(HWms * sfx);                   % half-window in samples
tRel = (-HW:HW)/sfx*1e3;                  % ms relative
outDir = fullfile(dataDir, 'VACC_TheVision_out');
if ~exist(outDir,'dir'), mkdir(outDir); end

% Select events by channel count
chCounts = sum(ech,2);
evtIdx = find(chCounts>=minCh & chCounts<=maxCh);
if isempty(evtIdx)
    fprintf('No events within %d–%d channels\n', minCh,maxCh);
    return;
end

fprintf('Processing %d events (±%.1f ms)...\n', numel(evtIdx), HWms*1e3);

% ---------- Main loop ----------
for ei = 1:numel(evtIdx)
    e = evtIdx(ei);
    active = ech(e,1:nCh);
    nActive = sum(active);
    anchor = round(mean(ets(e,:)));
    s0 = max(1, anchor - HW);
    s1 = min(size(d,2), anchor + HW);
    Ymat = d(:, s0:s1);
    if isempty(Ymat)
        fprintf('Evt %d skipped (out of bounds)\n', e);
        continue;
    end

    % Compute y-limits
    maxAbs = max(abs(Ymat(:)));
    if ~isfinite(maxAbs)||maxAbs==0, maxAbs = 1; end
    yL = 1.05*maxAbs*[-1 1];

    % ---------- Plot ----------
    f = figure('Color','w','Position',[60 60 900 min(120+90*nCh,5000)],'Visible','off');
    tl = tiledlayout(f, nCh, 1, 'Padding','compact','TileSpacing','compact');

    for c = 1:nCh
        nexttile(tl);
        hold on; box on; grid on;
        isAct = logical(active(c));
        if isAct
            lw = 1.4; col = [0 0 0];
        else
            lw = 0.6; col = [0.6 0.6 0.6];
        end
        plot(tRel, Ymat(c,1:numel(tRel)), 'Color', col, 'LineWidth', lw);
        xline(0,'--k'); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);
        title(sprintf('CSC%d%s', nums(c), tern(isAct,' *','')), 'FontSize',8);
        if c==nCh, xlabel('ms'); end
        ylabel('\muV');
    end

    sgtitle(tl, sprintf('Evt %03d | %d ch | ±%.0f ms | yLim ±%.1f µV',...
        e,nActive,HW/sfx*1e3,yL(2)), 'FontSize',12,'FontWeight','bold');

    outPng = fullfile(outDir, sprintf('Evt%03d_%dch.png', e, nActive));
    exportgraphics(f,outPng,'Resolution',220);
    close(f);
    fprintf('Saved %s\n', outPng);
end

fprintf('Done. Output dir: %s\n', outDir);
end

function s = tern(c,a,b)
if c, s=a; else, s=b; end
end
