function EventStacks_AmpWidth(excelPath, dataMatPath, varargin)

p = inputParser;
p.addRequired('excelPath', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));

% Data / channels / scaling
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);

% Alignment of display center
p.addParameter('align','midpoint', @(s) any(strcmpi(s,{'midpoint','peak'})));  % keep midpoint to preserve lags

% Windows
p.addParameter('displayHalfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);  % plotting window (±30 ms default)
p.addParameter('metricHalfWidthMs',  5e-3,  @(x)isfinite(x)&&x>0);  % metrics window  (±5 ms)  << updated

% Excel mapping & bounds
p.addParameter('indexBase','auto', @(s) any(strcmpi(s,{'auto','zero','one'})));
p.addParameter('evtOffset',0, @(x)isscalar(x)&&isfinite(x));
p.addParameter('maxEvents',[], @(x) isempty(x) || (isscalar(x) && x>0));

% Output
p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.addParameter('tag','ALL', @(s)ischar(s)||isstring(s));

p.parse(excelPath, dataMatPath, varargin{:});

excelPath      = string(p.Results.excelPath);
dataMatPath    = string(p.Results.dataMatPath);
channelIndices = p.Results.channelIndices;
scaleToMicroV  = p.Results.scaleToMicroV;
alignMode      = lower(string(p.Results.align));
displayHWms    = p.Results.displayHalfWidthMs;
metricHWms     = p.Results.metricHalfWidthMs;   % now ±5 ms by default
indexBase      = lower(string(p.Results.indexBase));
evtOffset      = p.Results.evtOffset;
maxEvents      = p.Results.maxEvents;
saveDir        = string(p.Results.saveDir);
tagStr         = string(p.Results.tag);

assert(isfile(excelPath),  'Excel not found: %s', excelPath);
assert(isfile(dataMatPath),'Data MAT not found: %s', dataMatPath);

% --- Load raw data ---
mf = matfile(dataMatPath);
try sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRowsAll = size(mf,'d',1);
nSamp    = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end %#ok<NASGU>

if isempty(channelIndices)
    chList = 1:nRowsAll;
else
    chList = channelIndices(:).';
    chList = chList(chList>=1 & chList<=nRowsAll);
end
nCh = numel(chList);

if saveDir==""
    [saveDir,~,~] = fileparts(excelPath);
end
if ~exist(saveDir,'dir'), mkdir(saveDir); end

% --- Read Excel & normalize to sample indices ---
T = readtable(excelPath, 'ReadVariableNames', true);
canon = lower(regexprep(T.Properties.VariableNames, '[^a-zA-Z0-9]', ''));
i_onSamp  = find(strcmp(canon,'onsamp')  | strcmp(canon,'startsample') | strcmp(canon,'startsamp') | strcmp(canon,'on'), 1);
i_offSamp = find(strcmp(canon,'offsamp') | strcmp(canon,'endsample')   | strcmp(canon,'endsamp')   | strcmp(canon,'off'), 1);
i_onSec   = find(strcmp(canon,'onsec')   | strcmp(canon,'startsec')    | strcmp(canon,'onsecs'), 1);
i_offSec  = find(strcmp(canon,'offsec')  | strcmp(canon,'endsec')      | strcmp(canon,'offsecs'), 1);

if ~isempty(i_onSamp) && ~isempty(i_offSamp)
    onSamp  = double(T{:, i_onSamp});
    offSamp = double(T{:, i_offSamp});
elseif ~isempty(i_onSec) && ~isempty(i_offSec)
    onSamp  = round(double(T{:, i_onSec})  * sfx);
    offSamp = round(double(T{:, i_offSec}) * sfx);
else
    if width(T) < 2, error('Excel must have [on_samp, off_samp] or [on_sec, off_sec].'); end
    onSamp  = double(T{:,1});
    offSamp = double(T{:,2});
end

switch indexBase
    case "zero", onSamp = onSamp+1; offSamp = offSamp+1;
    case "auto"
        if any(onSamp < 1 | offSamp < 1 | onSamp==0 | offSamp==0)
            onSamp = onSamp+1; offSamp = offSamp+1;
        end
    case "one"
        % no-op
end

NeventsAll = numel(onSamp);
onSamp  = max(1, min(onSamp,  nSamp));
offSamp = max(1, min(offSamp, nSamp));
Nevents = NeventsAll;
if ~isempty(maxEvents), Nevents = min(NeventsAll, maxEvents); end

% --- Windows (samples & time axes) ---
HWdisp   = max(1, round(displayHWms * sfx));      % display half-width in samples
HWmet    = max(1, round(metricHWms  * sfx));      % metric half-width in samples (±5 ms)
tRelDisp = (-HWdisp:HWdisp) / sfx * 1e3;          % ms

fprintf('EventStacks_AmpWidth: %d event rows (using %d), %d channels, sfx=%.1f Hz, display ±%.1f ms, metrics ±%.1f ms\n', ...
    NeventsAll, Nevents, nCh, sfx, 1e3*HWdisp/sfx, 1e3*HWmet/sfx);

% --- Iterate events ---
nBad = 0;
for e = 1:Nevents
    rowXL = e + evtOffset;
    if rowXL < 1 || rowXL > NeventsAll
        alt = e;
        if alt >= 1 && alt <= NeventsAll
            rowXL = alt;
        else
            nBad = nBad + 1; continue;
        end
    end
    s0_ev = max(1, round(onSamp(rowXL)));
    s1_ev = min(nSamp, round(offSamp(rowXL)));
    if ~isfinite(s0_ev) || ~isfinite(s1_ev) || s1_ev <= s0_ev
        nBad = nBad + 1; continue;
    end

    % Display center (midpoint) to preserve temporality
    anchor = round((s0_ev + s1_ev)/2);

    s0_disp = max(1, anchor - HWdisp);
    s1_disp = min(nSamp, anchor + HWdisp);

    % --- Figure (one per event) ---
    perRowPx = 92; basePx = 230; maxPx = 5200;
    figH = min(maxPx, basePx + perRowPx * nCh);
    f = figure('Color','w','Position',[60 60 980 figH],'Visible','off');
    tl = tiledlayout(f, nCh, 1, 'Padding','compact','TileSpacing','compact');

    % consistent y-limits across channels for this event
    yMaxAbs = 1;
    for k = 1:nCh
        ch = chList(k);
        yplot = double(mf.d(ch, s0_disp:s1_disp)) * scaleToMicroV;
        if ~isempty(yplot)
            yMaxAbs = max(yMaxAbs, max(abs(yplot(~isnan(yplot)))));
        end
    end
    yPad = 1.08; yL = [-yPad*yMaxAbs, yPad*yMaxAbs];

    for k = 1:nCh
        ch = chList(k);

        % --- Signals: display and metrics (metrics limited to ±5 ms around anchor) ---
        yplot = double(mf.d(ch, s0_disp:s1_disp)) * scaleToMicroV;     % for plotting (±display)
        s0_met = max(1, anchor - HWmet);
        s1_met = min(nSamp, anchor + HWmet);
        ymet  = double(mf.d(ch, s0_met:s1_met)) * scaleToMicroV;       % for metrics only (±5 ms)

        % --- Compute amplitude (absolute extremum) & half-width at half-amplitude within metric window ---
        amp_uV = NaN; width_ms = NaN; tPk_ms = NaN; tL_ms = NaN; tR_ms = NaN;

        if ~isempty(ymet) && all(isfinite(ymet)) && numel(ymet) >= 5
            [maxVal, kMax] = max(ymet);
            [minVal, kMin] = min(ymet);

            if abs(minVal) > abs(maxVal)
                sgn   = -1;                   % negative-going peak
                amp_uV = abs(minVal);         % amplitude as positive magnitude from 0
                pkRel = kMin;
            else
                sgn   = +1;                   % positive-going peak
                amp_uV = abs(maxVal);
                pkRel = kMax;
            end

            % Half-amplitude level (relative to zero)
            h = 0.5 * amp_uV;                 % positive scalar
            sig = sgn * ymet;                 % flip so the chosen peak is positive
            % left crossing (>= h to < h)
            kL = pkRel;
            while kL > 1 && sig(kL) >= h, kL = kL - 1; end
            if kL >= 1 && (kL+1) <= numel(sig)
                x0=kL; y0=sig(kL); x1=kL+1; y1=sig(kL+1);
                left_ip = x0 + (h - y0) / (y1 - y0);
            else
                left_ip = NaN;
            end
            % right crossing
            kR = pkRel; L = numel(sig);
            while kR < L && sig(kR) >= h, kR = kR + 1; end
            if (kR-1) >= 1 && kR <= L
                x0=kR-1; y0=sig(kR-1); x1=kR; y1=sig(kR);
                right_ip = x0 + (h - y0) / (y1 - y0);
            else
                right_ip = NaN;
            end

            if isfinite(left_ip) && isfinite(right_ip) && right_ip > left_ip
                width_samp = right_ip - left_ip;
                width_ms   = (width_samp / sfx) * 1e3;

                % Convert to display-time axis (relative to anchor)
                tPk_ms = ((s0_met + pkRel    - 1) - anchor) / sfx * 1e3;
                tL_ms  = ((s0_met + left_ip  - 1) - anchor) / sfx * 1e3;
                tR_ms  = ((s0_met + right_ip - 1) - anchor) / sfx * 1e3;
            end
        end

        % --- Plot ---
        nexttile(tl); hold on; box on; grid on;
        if ~isempty(yplot)
            plot(tRelDisp, yplot, 'LineWidth', 1.5);
        end
        xline(0,'--k','LineWidth',0.9); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);

        % half-width markers: RED and thicker, plus red baseline segment
        if isfinite(tL_ms) && isfinite(tR_ms)
            xline(tL_ms, '-', 'Color',[0.85 0.10 0.10], 'LineWidth',2.2, 'HandleVisibility','off');
            xline(tR_ms, '-', 'Color',[0.85 0.10 0.10], 'LineWidth',2.2, 'HandleVisibility','off');
            plot([tL_ms tR_ms],[0 0], '-', 'Color',[0.85 0.10 0.10], 'LineWidth',1.4, 'HandleVisibility','off');
        end

        % peak dot (only if within display window)
        if isfinite(tPk_ms) && tPk_ms >= tRelDisp(1) && tPk_ms <= tRelDisp(end) && isfinite(amp_uV)
            plot(tPk_ms, sgn*amp_uV, 'o', 'MarkerSize', 4.5, ...
                 'MarkerFaceColor',[0 0 0], 'MarkerEdgeColor','none', 'HandleVisibility','off');
        end

        % Per-channel title (UNBOLDED) with metrics
        if ~isempty(kept_channels)
            chName = sprintf('row %d (CSC%d)', ch, kept_channels(ch));
        else
            chName = sprintf('row %d', ch);
        end
        if isfinite(amp_uV) && isfinite(width_ms)
            ttlTxt = sprintf('%s  |  amp=%.1f \\muV  |  HW=%.2f ms', chName, amp_uV, width_ms);
        else
            ttlTxt = sprintf('%s  |  amp=NA  |  HW=NA', chName);
        end
        title(ttlTxt, 'FontSize',9, 'FontWeight','normal');   % <-- unbolded

        ax = gca; ax.FontSize = 8;
        if k < nCh, ax.XTickLabel = []; else, xlabel('ms'); end
        ylabel('\muV');
    end

    sg = sprintf('Event %d  |  align: midpoint  |  display: \\pm%.1f ms  |  metrics: \\pm%.1f ms  |  channels=%d  |  %s', ...
                 e, 1e3*HWdisp/sfx, 1e3*HWmet/sfx, nCh, tagStr);
    sgtitle(tl, sg, 'FontSize',12,'FontWeight','bold');

    outPng = fullfile(saveDir, sprintf('Evt%03d_Stack_ampHW_align-midpoint_dispHW%ds_metHW%ds.png', ...
        e, HWdisp, HWmet));
    exportgraphics(f, outPng, 'Resolution', 220);
    close(f);
    fprintf('Saved: %s\n', outPng);
end

if nBad>0
    fprintf('Skipped %d event(s) (bad/missing indices/out-of-bounds).\n', nBad);
end
end
