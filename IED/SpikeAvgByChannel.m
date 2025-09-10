function SpikeAvgByChannel(dataMatPath, spikesMatPath, varargin)
% SpikeAvgByEventRank
% Assign each event a rank by number of participating channels:
%   - Rank 1 = event with MOST channels
%   - Last rank = event with only 1 channel
% Ranks are sequential (no gaps).
%
% For each channel, for each RANKED EVENT that includes that channel:
%   - Extract window anchored at the per-event, per-channel PEAK
%   - Compute mean ± STD (STD=0 if only one window)
%   - Plot and save PNG with:
%       * Channel row + CSC# (CSC in RED if 22–34)
%       * Rank number (Rank 001, Rank 002, …)
%       * Tiny footer: total # of channels in that event and list of CSCs
%       * Events used, peak amplitude, STD@peak
%
% Files saved as:
%   Rank<rnk>_ch###_CSC##_HW<samples>_<ms>.png
%
% EXAMPLE:
% SpikeAvgByEventRank('LL_input_data.mat','LLspikes.mat', ...
%    'halfWidthMs',0.030,'peakPolarity','abs','saveDir','C:\tmp\ranked')

% ---- Parse inputs ----
p = inputParser;
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));
p.addRequired('spikesMatPath', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);
p.addParameter('peakPolarity','abs', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('scaleToMV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.parse(dataMatPath, spikesMatPath, varargin{:});

halfWidthMs    = p.Results.halfWidthMs;
peakPolarity   = lower(string(p.Results.peakPolarity));
scaleToMV      = p.Results.scaleToMV;
saveDir        = string(p.Results.saveDir);
channelIndices = p.Results.channelIndices;

% ---- Open data & spikes ----
if ~isfile(dataMatPath), error('Data MAT not found: %s', dataMatPath); end
if ~isfile(spikesMatPath), error('Spikes MAT not found: %s', spikesMatPath); end

mf = matfile(dataMatPath);
try
    sfx = mf.sfx;        % samples/sec
catch
    error('Sampling rate "sfx" is required.');
end
HW = max(1, round(halfWidthMs * sfx));   % half-width in samples

try kept_channels = mf.kept_channels; catch, kept_channels = []; end

nRows = size(mf,'d',1);
nSamp = size(mf,'d',2);

S = load(spikesMatPath,'ets','ech');
if ~isfield(S,'ets'), error('Spikes file must contain ets (Nx2 on/off).'); end
ets = S.ets; Nevents = size(ets,1);

if isfield(S,'ech')
    ech = S.ech;
    if size(ech,2) ~= nRows
        if size(ech,2) < nRows, ech(:,end+1:nRows) = false; else, ech = ech(:,1:nRows); end
    end
else
    ech = true(Nevents, nRows);
end

% Output directory
if saveDir=="", [outDir,~,~] = fileparts(dataMatPath); else, outDir = char(saveDir); end
if ~exist(outDir,'dir'), mkdir(outDir); end

% Channels to process
if isempty(channelIndices), chList = 1:nRows;
else, chList = channelIndices(:).'; chList = chList(chList>=1 & chList<=nRows);
end

% Time axis
tRelSamples = -HW:HW;
tRelMs = (tRelSamples / sfx) * 1e3;

% --- Event participation counts & ranking (Rank 1 = highest participation) ---
partCount = sum(ech,2);                         % channels per event
[~, sortIdx] = sort(partCount,'descend');       % indices by decreasing participation
rankOfEvent = zeros(Nevents,1);
rankOfEvent(sortIdx) = 1:Nevents;               % sequential ranks 1..Nevents (fills gaps)

fprintf('Assigned ranks 1..%d to %d events.\n', Nevents, Nevents);

for ch = chList
    % Channel label
    if ~isempty(kept_channels)
        chCSC = kept_channels(ch); cscStr = sprintf('CSC%d', chCSC);
    else
        chCSC = NaN; cscStr = 'CSCNA';
    end

    for rnk = 1:Nevents
        % This rank corresponds to exactly ONE event; include it only if that event fired on this channel
        idxGroup = find(rankOfEvent==rnk & ech(:,ch));
        if isempty(idxGroup), continue; end

        % Collect window for this (channel, event) using PEAK anchor
        X = collectWindowsPeak(mf, ets(idxGroup,:), ch, peakPolarity, HW, nSamp, scaleToMV);
        if isempty(X), continue; end

        % Mean ± STD (handle single window case: STD = zeros)
        mu = mean(X,1,'omitnan');
        if size(X,1) == 1
            sd = zeros(1, size(X,2));
        else
            sd = std(X,0,1,'omitnan');
        end

        [peakAmp, sdAtPeak, tAtPeakMs] = peakMetrics(mu, sd, tRelMs);

        % Tiny footer: list ALL CSCs that participated in THIS ranked event
        ev = idxGroup(1);
        cols = find(ech(ev,:));
        if ~isempty(kept_channels)
            cscList = kept_channels(cols);
            chanListStr = strjoin(arrayfun(@(z) sprintf('CSC%d', z), cscList, 'UniformOutput', false), ' ');
        else
            chanListStr = strjoin(arrayfun(@num2str, cols, 'UniformOutput', false), ' ');
        end
        chanText = sprintf('%d channel(s): %s', numel(cols), chanListStr);

        % --- Figure ---
        f = figure('Color','w','Position',[80 80 980 560],'Visible','off');
        ax = axes('Parent',f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        shadedMean(ax, tRelMs, mu, sd);
        xlabel(ax,'Time relative to PEAK anchor (ms)'); ylabel(ax,'Amplitude (mV)');

        % Title with CSC in RED if 22–34
        if ~isnan(chCSC) && chCSC>=22 && chCSC<=34
            cscDisp = sprintf('\\color{red}CSC%d\\color{black}', chCSC);
        elseif ~isnan(chCSC)
            cscDisp = sprintf('CSC%d', chCSC);
        else
            cscDisp = 'CSCNA';
        end
        ttl = sprintf('Rank %03d | row %d (%s) | used %d | peak=%.3f mV @ %.2f ms | STD@peak=%.3f mV', ...
            rnk, ch, cscDisp, size(X,1), peakAmp, tAtPeakMs, sdAtPeak);
        title(ax, ttl, 'Interpreter','tex');

        % Tiny footer
        text(ax,0.01,0.01,chanText,'Units','normalized','FontSize',6,'VerticalAlignment','bottom','Interpreter','none');

        % Save (rank prefix ensures folder sorts Rank001, Rank002, …)
        outPng = fullfile(outDir, sprintf('Rank%03d_ch%03d_%s_HW%ds_%dms.png', ...
            rnk, ch, cscStr, HW, round(1e3*HW/sfx)));
        exportgraphics(f,outPng,'Resolution',220);
        close(f);
        fprintf('Saved: %s\n', outPng);
    end
end

fprintf('Done. Ranked images saved to: %s\n', outDir);

% ====================== helpers ======================
function X = collectWindowsPeak(mf, ets_sub, ch, peakPolarity, HW, nSamp, scaleToMV)
    Ne = size(ets_sub,1); X = nan(Ne,2*HW+1);
    for i = 1:Ne
        s0_ev = max(1, ets_sub(i,1)); s1_ev = min(nSamp, ets_sub(i,2));
        anchor = localPeakAnchor(mf,ch,s0_ev,s1_ev,peakPolarity);
        s0 = anchor-HW; s1 = anchor+HW; if s0<1||s1>nSamp, continue; end
        y = double(mf.d(ch,s0:s1))*scaleToMV; X(i,:) = y;
    end
    X = X(all(isfinite(X),2),:);
end

function anchor = localPeakAnchor(mf,row,s0,s1,polarity)
    y = double(mf.d(row,s0:s1));
    switch lower(polarity)
        case 'pos', [~,k] = max(y);
        case 'neg', [~,k] = min(y);
        otherwise, [~,k] = max(abs(y));
    end
    anchor = s0+k-1;
end

function shadedMean(ax,x,mu,sd)
    if isempty(mu)||all(~isfinite(mu)),return;end
    yu=mu+sd; yl=mu-sd; xp=[x,fliplr(x)]; yp=[yu,fliplr(yl)];
    patch('Parent',ax,'XData',xp,'YData',yp,'FaceColor',[0.3 0.3 0.9],'FaceAlpha',0.25,'EdgeColor','none');
    plot(ax,x,mu,'LineWidth',1.8);
    yline(ax,0,':','Color',[0.6 0.6 0.6]); xline(ax,0,'--k','LineWidth',1.0);
end

function [peakAmp,sdAtPeak,tAtPeakMs] = peakMetrics(mu,sd,tRelMs)
    [~,k]=max(abs(mu)); peakAmp=mu(k); sdAtPeak=sd(k); tAtPeakMs=tRelMs(k);
end

end
