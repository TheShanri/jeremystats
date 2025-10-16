function VACC_TheVision(dataDir, varargin)
% -------------------------------------------------------------------------
% VACC_TheVision — Event visualizer for VACC IED pipeline
%
% Loads ets.mat / ech.mat and all CSC*.ncs files in a folder.
% Plots ±50 ms windows around each event (midpoint anchor).
%
% Example:
%   VACC_TheVision("D:\PTEN\M13_pten\HF4s\IED DATA");
%
% -------------------------------------------------------------------------

%% Parameters
p = inputParser;
p.addRequired('dataDir', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 50, @(x)isfinite(x)&&x>0); % ±50 ms
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('minCh', 6, @(x)isfinite(x)&&x>=0);
p.addParameter('maxCh', 8, @(x)isfinite(x)&&x>=0);
p.addParameter('evenOnly', true, @(x)islogical(x));
p.parse(dataDir, varargin{:});
dataDir = string(p.Results.dataDir);
halfWidthMs   = p.Results.halfWidthMs;
scaleFactor   = p.Results.scaleToMicroV;
minCh         = p.Results.minCh;
maxCh         = p.Results.maxCh;
evenOnly      = p.Results.evenOnly;

sfx = 30000;                         % sampling rate
HW  = round((halfWidthMs/1000) * sfx); % samples per half-window
tRel = (-HW:HW)/sfx*1e3;             % time axis in ms

fprintf('\n=== VACC_TheVision ===\n');

%% Load event data
load(fullfile(dataDir,'ets.mat'),'ets');
load(fullfile(dataDir,'ech.mat'),'ech');
fprintf('Loaded %d events × %d channels\n', size(ets,1), size(ech,2));

%% Locate CSC files
files = dir(fullfile(dataDir,'CSC*.ncs'));
if isempty(files), error('No CSC*.ncs found.'); end
nums = cellfun(@(n) sscanf(n,'CSC%d.ncs'), {files.name});
valid = ~isnan(nums);
if evenOnly, valid = valid & mod(nums,2)==0; end
files = files(valid); nums = nums(valid);
[nums, order] = sort(nums); files = files(order);
nCh = numel(files);
fprintf('Using %d %s-numbered channels\n', nCh, tern(evenOnly,'even','all'));

%% Load all channels (full files)
fprintf('Loading channel data (may take a while)...\n');
data = cell(1,nCh);
for i = 1:nCh
    fname = fullfile(dataDir, files(i).name);
    try
        % === The correct 5-output call ===
        [~,~,~,~,samples] = Nlx2MatCSC(fname, [0 0 0 0 1], 0, 1, []);
        s = reshape(samples,1,[]);
        s = single(-s) * scaleFactor;     % invert, scale
        data{i} = s;
    catch ME
        fprintf('  !! %s failed: %s\n', files(i).name, ME.message);
        data{i} = [];
    end
end

maxlen = max(cellfun(@numel,data));
fprintf('Longest channel: %.1f sec\n', maxlen/sfx);

D = zeros(nCh, maxlen,'single');
for i = 1:nCh
    v = data{i};
    if isempty(v), continue; end
    D(i,1:numel(v)) = v;
end
clear data

%% Event selection
chCount = sum(ech(:,1:nCh),2);
sel = (chCount>=minCh) & (chCount<=maxCh);
evtIdx = find(sel);
fprintf('Plotting %d events (6–8ch)\n', numel(evtIdx));

outDir = fullfile(dataDir,'VACC_TheVision_out');
if ~exist(outDir,'dir'), mkdir(outDir); end

%% Iterate events
for ii = 1:numel(evtIdx)
    e = evtIdx(ii);
    active = logical(ech(e,1:nCh));
    nActive = sum(active);

    anchor = round(mean(ets(e,:)));
    s0 = max(1, anchor - HW);
    s1 = min(size(D,2), anchor + HW);

    if s1 <= s0
        fprintf('Evt %d skipped (out of range)\n', e);
        continue;
    end

    Y = D(:,s0:s1);
    maxAbs = max(abs(Y(:)));
    if maxAbs==0 || ~isfinite(maxAbs), maxAbs=1; end
    yL = 1.05*maxAbs*[-1 1];

    % ---------- Plot ----------
    figH = min(150 + 90*nCh, 5000);
    f = figure('Color','w','Position',[100 100 900 figH],'Visible','off');
    tl = tiledlayout(f,nCh,1,'Padding','compact','TileSpacing','compact');

    for ch = 1:nCh
        nexttile(tl);
        hold on; box on; grid on;
        if active(ch)
            lw = 1.4; col=[0 0 0];
        else
            lw = 0.6; col=[0.6 0.6 0.6];
        end
        plot(tRel,Y(ch,1:numel(tRel)),'Color',col,'LineWidth',lw);
        xline(0,'--k'); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);
        title(sprintf('CSC%d%s',nums(ch),tern(active(ch),' *','')),'FontSize',8);
        if ch==nCh, xlabel('ms'); end
        ylabel('\muV');
    end

    sgtitle(tl,sprintf('Evt %03d | %d ch | ±%.0f ms | yLim ±%.1f µV',...
        e,nActive,halfWidthMs,yL(2)),...
        'FontSize',12,'FontWeight','bold');

    outPng = fullfile(outDir,sprintf('Evt%03d_%dch.png',e,nActive));
    exportgraphics(f,outPng,'Resolution',220);
    close(f);
    fprintf('Saved %s\n', outPng);
end

fprintf('\nDone. Output saved in %s\n', outDir);
end

function s = tern(c,a,b)
if c, s=a; else, s=b; end
end
