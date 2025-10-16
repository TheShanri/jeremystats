function TheVision_vacc(dataDir, varargin)
% TheVision_vacc — Plot IED events directly from Neuralynx .ncs files
% Usage: TheVision_vacc('path/to/IED DATA')
%
% Requirements:
%   • LLspikedetector outputs: ets.mat, ech.mat in same folder
%   • Neuralynx converter: Nlx2MatCSC.m/.mex in path
%
% Default behavior:
%   - Uses only even-numbered CSC channels
%   - Window ±50 ms around event midpoint
%   - Plots one column (rows = channels)
%
% Optional name/value:
%   'HalfWidthMs', 'MinCh', 'MaxCh', 'EvenOnly', 'ScaleToMicroV'

% ---------- Parse ----------
p = inputParser;
p.addRequired('dataDir', @(s)ischar(s)||isstring(s));
p.addParameter('HalfWidthMs', 50, @(x)isfinite(x)&&x>0);
p.addParameter('MinCh', 6, @(x)isfinite(x));
p.addParameter('MaxCh', 8, @(x)isfinite(x));
p.addParameter('EvenOnly', true, @(x)islogical(x)||ismember(x,[0 1]));
p.addParameter('ScaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.parse(dataDir, varargin{:});

dataDir = string(dataDir);
halfWidthMs   = p.Results.HalfWidthMs;
minCh         = p.Results.MinCh;
maxCh         = p.Results.MaxCh;
evenOnly      = logical(p.Results.EvenOnly);
scaleToMicroV = p.Results.ScaleToMicroV;

sfx = 30000; % Hz (fixed)
HW  = round((halfWidthMs/1000)*sfx);

% ---------- Load spike info ----------
S = load(fullfile(dataDir,'ets.mat'));
ets = S.ets;
S = load(fullfile(dataDir,'ech.mat'));
ech = S.ech;
Nevents = size(ets,1);

% ---------- Get list of CSC files ----------
files = dir(fullfile(dataDir,'CSC*.ncs'));
if isempty(files)
    error('No .ncs files found in %s',dataDir);
end
names = {files.name};
nums  = cellfun(@(s) sscanf(s,'CSC%d.ncs'), names);
if evenOnly
    keep = mod(nums,2)==0 & ~isnan(nums);
    files = files(keep);
    nums  = nums(keep);
end
nCh = numel(files);
fprintf('Loaded %d channel files (%s).\n', nCh, tern(evenOnly,'even only','all'));

% ---------- Event selection ----------
chCounts = sum(ech,2);
sel = (chCounts>=minCh)&(chCounts<=maxCh);
evtIdx = find(sel);
if isempty(evtIdx)
    fprintf('No events with %d–%d channels.\n',minCh,maxCh);
    return;
end
fprintf('%d qualifying events. Window ±%d ms (±%d samples)\n',numel(evtIdx),halfWidthMs,HW);

outDir = fullfile(dataDir,'IED_PLOTS');
if ~exist(outDir,'dir'), mkdir(outDir); end

% ---------- Iterate events ----------
for ii = 1:numel(evtIdx)
    e = evtIdx(ii);
    s0 = max(1, round(mean(ets(e,:))) - HW);
    s1 = s0 + 2*HW;

    activeMask = ech(e,:);
    nActive = sum(activeMask);

    Y = zeros(nCh, 2*HW+1, 'single');
    for k = 1:nCh
        fn = fullfile(files(k).folder, files(k).name);
        try
            seg = Nlx2MatCSC(fn, [0 0 0 0 1], 0, 4, [s0 s1]); % Extract samples by record range
            y = reshape(seg,1,[]);
            if numel(y)<2*HW+1, y(end+1:2*HW+1)=NaN; end
            Y(k,:) = single(-y)*scaleToMicroV;
        catch
            Y(k,:) = NaN;
        end
    end

    maxAbs = max(abs(Y(:)),'omitnan');
    if ~isfinite(maxAbs)||maxAbs==0, maxAbs=1; end
    yL = 1.05*maxAbs*[-1 1];
    tRelMs = (-HW:HW)/sfx*1e3;

    f=figure('Color','w','Position',[60 60 900 min(400+80*nCh,5000)],'Visible','off');
    tl=tiledlayout(f,nCh,1,'Padding','compact','TileSpacing','compact');

    for k=1:nCh
        nexttile(tl);
        hold on; box on;
        plot(tRelMs,Y(k,:),'Color',tern(activeMask(k),[0 0 0],[0.6 0.6 0.6]),...
             'LineWidth',tern(activeMask(k),1.2,0.6));
        xline(0,'--k','LineWidth',0.6);
        ylim(yL);
        ylabel('\muV');
        title(sprintf('CSC%d%s',nums(k),tern(activeMask(k),' *','')),'FontSize',8);
        if k<nCh, set(gca,'XTickLabel',[]); else, xlabel('ms'); end
    end

    sgtitle(tl,sprintf('Event %03d  |  Active %dch  |  ±%d ms',e,nActive,halfWidthMs),'FontSize',12);
    exportgraphics(f,fullfile(outDir,sprintf('Evt%03d_%dch.png',e,nActive)),'Resolution',220);
    close(f);
    fprintf('Saved Evt%03d\n',e);
end

fprintf('All done → %s\n',outDir);
end

% --- tiny ternary helper ---
function y=tern(c,a,b)
if c, y=a; else, y=b; end
end
