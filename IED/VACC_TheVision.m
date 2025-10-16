function VACC_TheVision(dataDir, varargin)
% VACC_TheVision — live IED visualizer (no pre-saved data MAT)
% Reads Neuralynx CSC files on demand, loads ets/ech from same folder,
% and plots ±50 ms event windows with all channels stacked in one column.
%
% Usage:
%   VACC_TheVision("D:\PTEN\M13_pten\HF4s\IED DATA");
%
% Optional Name–Value pairs:
%   'halfWidthMs'   default 50e-3   % ±50 ms window
%   'scaleToMicroV' default 1
%   'minCh'         default 6
%   'maxCh'         default 8
%
% Output:
%   One PNG per qualifying event, saved in <dataDir>/VACC_TheVision_out/

% ---------- Parse ----------
p = inputParser;
p.addRequired('dataDir', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 50e-3, @(x)isfinite(x)&&x>0);
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('minCh', 6, @(x)isfinite(x)&&x>=0);
p.addParameter('maxCh', 8, @(x)isfinite(x)&&x>=0);
p.parse(dataDir, varargin{:});
dataDir = string(p.Results.dataDir);
HWms = p.Results.halfWidthMs;
scaleToMicroV = p.Results.scaleToMicroV;
minCh = p.Results.minCh;
maxCh = p.Results.maxCh;

% ---------- Load spike info ----------
etsFile = fullfile(dataDir, "ets.mat");
echFile = fullfile(dataDir, "ech.mat");
if ~isfile(etsFile) || ~isfile(echFile)
    error("ets.mat or ech.mat not found in %s", dataDir);
end
load(etsFile, "ets");
load(echFile, "ech");
fprintf("Loaded %d events × %d channels from ets/ech\n", size(ets,1), size(ech,2));

% ---------- Setup ----------
sfx = 30000;                              % fixed sampling rate (Hz)
HW = round(HWms * sfx);                   % half-window in samples
tRel = (-HW:HW) / sfx * 1e3;              % relative time (ms)
files = dir(fullfile(dataDir, 'CSC*.ncs'));
if isempty(files), error('No CSC*.ncs in %s', dataDir); end
nCh = numel(files);

chCounts = sum(ech,2);
evtIdx = find(chCounts>=minCh & chCounts<=maxCh);
if isempty(evtIdx)
    fprintf('No events within %d–%d channels\n', minCh, maxCh);
    return;
end

outDir = fullfile(dataDir, 'VACC_TheVision_out');
if ~exist(outDir,'dir'), mkdir(outDir); end
fprintf('Processing %d events (±%.1f ms window)...\n', numel(evtIdx), HWms*1e3);

% ---------- Iterate events ----------
for ei = 1:numel(evtIdx)
    e = evtIdx(ei);
    active = ech(e,:);
    nActive = sum(active);
    anchor = round(mean(ets(e,:)));       % midpoint anchor
    s0 = anchor - HW; s1 = anchor + HW;
    if s0 < 1, s0 = 1; end

    % Read only windowed samples
    Y = cell(1,nCh);
    for c = 1:nCh
        fn = fullfile(dataDir, files(c).name);
        try
            % mode 4 = range in samples
            samp = Nlx2MatCSC(fn, [0 0 0 0 1], 0, 4, [s0 s1]);
            s = reshape(samp, 1, []);
            s = single(-s) * scaleToMicroV;     % invert polarity, scale
            Y{c} = s;
        catch ME
            fprintf('Ch%d failed: %s\n', c, ME.message);
            Y{c} = nan(1,2*HW+1);
        end
    end
    Ymat = cell2mat(Y'); % [nCh x samples]

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
        if active(c)
            lw = 1.4; col = [0 0 0];
        else
            lw = 0.6; col = [0.6 0.6 0.6];
        end
        plot(tRel, Ymat(c,:), 'Color', col, 'LineWidth', lw);
        xline(0,'--k'); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);
        title(sprintf('CSC%d%s', c, tern(active(c),' *','')), 'FontSize',8);
        if c==nCh, xlabel('ms'); end
        ylabel('\muV');
    end

    sgtitle(tl, sprintf('Evt %03d | %d ch | ±%.0f ms | yLim ±%.1f µV',...
        e, nActive, HW/sfx*1e3, yL(2)), 'FontSize',12,'FontWeight','bold');

    outPng = fullfile(outDir, sprintf('Evt%03d_%dch.png', e, nActive));
    exportgraphics(f,outPng,'Resolution',220);
    close(f);
    fprintf('Saved %s\n', outPng);
end

fprintf('All done. Output dir: %s\n', outDir);
end

function s = tern(c,a,b)
if c, s=a; else, s=b; end
end
