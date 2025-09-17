function EventStacks_AmpWidth(excelPath, dataMatPath, varargin)
% One PNG per event. Converts AD->µV, computes amplitude & half-width in ±5 ms,
% and uses a SINGLE, FIXED y-axis across ALL events so plots are comparable.

% ---------- Args ----------
p = inputParser;
p.addRequired('excelPath', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));

% Data / channels / scaling
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('scaleToMicroV', NaN, @(x) isnumeric(x) && all(x>0)); % scalar or per-channel vector (µV per AD count)
p.addParameter('adBitVolts', [], @(x) isempty(x) || (isnumeric(x) && all(x>0))); % alternative (V/bit); overrides scaleToMicroV if provided

% Alignment (display center)
p.addParameter('align','midpoint', @(s) any(strcmpi(s,{'midpoint','peak'})));  % midpoint preserves lags

% Windows
p.addParameter('displayHalfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);  % plotting window (±)
p.addParameter('metricHalfWidthMs',  5e-3,  @(x)isfinite(x)&&x>0);  % metrics window  (±)  -- amplitude & half-width only here

% Excel mapping & bounds
p.addParameter('indexBase','auto', @(s) any(strcmpi(s,{'auto','zero','one'})));
p.addParameter('evtOffset',0, @(x)isscalar(x)&&isfinite(x));
p.addParameter('maxEvents',[], @(x) isempty(x) || (isscalar(x) && x>0));

% Y-axis (global, fixed across ALL events)
p.addParameter('yLimitMicroV', [], @(x) isempty(x) || (isscalar(x) && x>0));     % force fixed ±yLimit
p.addParameter('yPercentile', 99.5, @(x) isscalar(x) && x>0 && x<=100);          % robust global scale if yLimitMicroV empty
p.addParameter('yPadFrac', 0.10, @(x) isscalar(x) && x>=0 && x<1);               % padding fraction on y-limits
p.addParameter('yFrom', 'display', @(s) any(strcmpi(s,{'display','metric'})));   % base y on display or metric window

% Output
p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.addParameter('tag','ALL', @(s)ischar(s)||isstring(s));

p.parse(excelPath, dataMatPath, varargin{:});

excelPath      = string(p.Results.excelPath);
dataMatPath    = string(p.Results.dataMatPath);
channelIndices = p.Results.channelIndices;
scaleToMicroV  = p.Results.scaleToMicroV;
adBitVolts     = p.Results.adBitVolts;    % V/bit
alignMode      = lower(string(p.Results.align));
displayHWms    = p.Results.displayHalfWidthMs;
metricHWms     = p.Results.metricHalfWidthMs;
indexBase      = lower(string(p.Results.indexBase));
evtOffset      = p.Results.evtOffset;
maxEvents      = p.Results.maxEvents;
yLimitMicroV   = p.Results.yLimitMicroV;
yPct           = p.Results.yPercentile;
yPad           = p.Results.yPadFrac;
yFrom          = lower(string(p.Results.yFrom));
saveDir        = string(p.Results.saveDir);
tagStr         = string(p.Results.tag);

assert(isfile(excelPath),  'Excel not found: %s', excelPath);
assert(isfile(dataMatPath),'Data MAT not found: %s', dataMatPath);

% ---------- Load raw data ----------
mf = matfile(dataMatPath);
try sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRowsAll = size(mf,'d',1);
nSamp    = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end %#ok<NASGU>

% Channel list
if isempty(channelIndices)
    chList = 1:nRowsAll;
else
    chList = channelIndices(:).';
    chList = chList(chList>=1 & chList<=nRowsAll);
end
nCh = numel(chList);

% Output dir
if saveDir==""
    [saveDir,~,~] = fileparts(excelPath);
end
if ~exist(saveDir,'dir'), mkdir(saveDir); end

% ---------- Determine scale (AD -> µV) ----------
if ~isempty(adBitVolts)
    % adBitVolts is V/bit → µV/bit
    scaleToMicroV = adBitVolts * 1e6;
end
if any(isnan(scaleToMicroV))
    error(['You must specify conversion from AD->µV.\n' ...
           'Pass ''scaleToMicroV'', e.g., 0.061035 (for ADBitVolts=6.1035e-8), or ''adBitVolts'' in V/bit.']);
end
% Allow per-channel vector
if numel(scaleToMicroV) == 1
    getScale = @(ch) scaleToMicroV;
else
    assert(numel(scaleToMicroV) >= max(chList), 'scaleToMicroV vector must have >= max(channel) elements.');
    getScale = @(ch) scaleToMicroV(ch);
end

% ---------- Read Excel & normalize to sample indices ----------
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

% ---------- Windows ----------
HWdisp   = max(1, round(displayHWms * sfx));      % display half-width (samples)
HWmet    = max(1, round(metricHWms  * sfx));      % metrics half-width (samples)
tRelDisp = (-HWdisp:HWdisp) / sfx * 1e3;          % ms axis for plotting

fprintf(['EventStacks_AmpWidth:\n  Events (rows in sheet) = %d (using %d)\n' ...
         '  Channels = %d\n  sfx = %.1f Hz\n  display=±%.1f ms, metrics=±%.1f ms\n'], ...
        NeventsAll, Nevents, nCh, sfx, 1e3*HWdisp/sfx, 1e3*HWmet/sfx);

% ---------- PASS 1: compute a FIXED y-limit for ALL events ----------
if isempty(yLimitMicroV)
    globalRob = 1;  % robust max abs
    for e = 1:Nevents
        rowXL = e + evtOffset;
        if rowXL < 1 || rowXL > NeventsAll, continue; end
        s0_ev = max(1, round(onSamp(rowXL)));
        s1_ev = min(nSamp, round(offSamp(rowXL)));
        if ~isfinite(s0_ev) || ~isfinite(s1_ev) || s1_ev <= s0_ev, continue; end

        % center for display
        anchor = round((s0_ev + s1_ev)/2);
        if yFrom=="metric"
            s0w = max(1, anchor - HWmet);  s1w = min(nSamp, anchor + HWmet);
        else % "display"
            s0w = max(1, anchor - HWdisp); s1w = min(nSamp, anchor + HWdisp);
        end

        for k = 1:nCh
            ch = chList(k);
            sc = getScale(ch);
            y = double(mf.d(ch, s0w:s1w)) * sc;   % µV
            if isempty(y), continue; end
            a = abs(y(:));
            if any(isfinite(a))
                r = prctile(a, yPct);
                if isfinite(r), globalRob = max(globalRob, r); end
            end
        end
    end
    yFix = (1+yPad) * globalRob;
else
    yFix = yLimitMicroV;  % user-specified
end
yL_fixed = [-yFix, yFix];
fprintf('Fixed y-limits (all events): ±%.1f µV (based on %s window, %.1f%%-tile, pad=%.0f%%)\n', ...
    yFix, yFrom, yPct, 100*yPad);

% ---------- PASS 2: generate figures (one PNG per event) ----------
nBad = 0;
for e = 1:Nevents
    rowXL = e + evtOffset;
    if rowXL < 1 || rowXL > NeventsAll
        continue;
    end
    s0_ev = max(1, round(onSamp(rowXL)));
    s1_ev = min(nSamp, round(offSamp(rowXL)));
    if ~isfinite(s0_ev) || ~isfinite(s1_ev) || s1_ev <= s0_ev
        nBad = nBad + 1; continue;
    end

    anchor = round((s0_ev + s1_ev)/2);
    s0_disp = max(1, anchor - HWdisp);
    s1_disp = min(nSamp, anchor + HWdisp);

    % Figure (one per event)
    perRowPx = 92; basePx = 230; maxPx = 5200;
    figH = min(maxPx, basePx + perRowPx * nCh);
    f = figure('Color','w','Position',[60 60 980 figH],'Visible','off');
    tl = tiledlayout(f, nCh, 1, 'Padding','compact','TileSpacing','compact');

    for k = 1:nCh
        ch = chList(k);
        sc = getScale(ch);

        % display signal
        yplot = double(mf.d(ch, s0_disp:s1_disp)) * sc;     % µV

        % metrics window
        s0_met = max(1, anchor - HWmet);
        s1_met = min(nSamp, anchor + HWmet);
        ymet   = double(mf.d(ch, s0_met:s1_met)) * sc;      % µV

        % Compute amplitude (absolute extremum in ±5 ms) & half-width at half-amplitude
        amp_uV = NaN; width_ms = NaN; tPk_ms = NaN; tL_ms = NaN; tR_ms = NaN; sgn = +1;

        if ~isempty(ymet) && all(isfinite(ymet)) && numel(ymet) >= 5
            [maxVal, kMax] = max(ymet);
            [minVal, kMin] = min(ymet);

            if abs(minVal) > abs(maxVal)
                sgn    = -1;                   % negative-going selected
                amp_uV = abs(minVal);          % magnitude from zero
                pkRel  = kMin;
            else
                sgn    = +1;
                amp_uV = abs(maxVal);
                pkRel  = kMax;
            end

            h = 0.5 * amp_uV;                  % half-amplitude level
            sig = sgn * ymet;                  % flip so selected peak is positive

            % left crossing
            kL = pkRel;
            while kL > 1 && sig(kL) >= h, kL = kL - 1; end
            if kL >= 1 && (kL+1) <= numel(sig)
                x0=kL; y0=sig(kL); x1=kL+1; y1=sig(kL+1);
                left_ip = x0 + (h - y0) / (y1 - y0);
            else
                left_ip = NaN;
            end
            % right crossing
            kR = pkRel; Lsig = numel(sig);
            while kR < Lsig && sig(kR) >= h, kR = kR + 1; end
            if (kR-1) >= 1 && kR <= Lsig
                x0=kR-1; y0=sig(kR-1); x1=kR; y1=sig(kR);
                right_ip = x0 + (h - y0) / (y1 - y0);
            else
                right_ip = NaN;
            end

            if isfinite(left_ip) && isfinite(right_ip) && right_ip > left_ip
                width_samp = right_ip - left_ip;
                width_ms   = (width_samp / sfx) * 1e3;

                % Convert metric indices to display time (ms)
                tPk_ms = ((s0_met + pkRel    - 1) - anchor) / sfx * 1e3;
                tL_ms  = ((s0_met + left_ip  - 1) - anchor) / sfx * 1e3;
                tR_ms  = ((s0_met + right_ip - 1) - anchor) / sfx * 1e3;
            end
        end

        % Plot
        nexttile(tl); hold on; box on; grid on;
        if ~isempty(yplot)
            plot(tRelDisp, yplot, 'LineWidth', 1.5);
        end
        xline(0,'--k','LineWidth',0.9); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL_fixed);

        % half-width markers (red) + base segment
        if isfinite(tL_ms) && isfinite(tR_ms)
            xline(tL_ms, '-', 'Color',[0.85 0.10 0.10], 'LineWidth',2.2, 'HandleVisibility','off');
            xline(tR_ms, '-', 'Color',[0.85 0.10 0.10], 'LineWidth',2.2, 'HandleVisibility','off');
            plot([tL_ms tR_ms],[0 0], '-', 'Color',[0.85 0.10 0.10], 'LineWidth',1.4, 'HandleVisibility','off');
        end

        % peak dot
        if isfinite(tPk_ms) && tPk_ms >= tRelDisp(1) && tPk_ms <= tRelDisp(end) && isfinite(amp_uV)
            plot(tPk_ms, sgn*amp_uV, 'o', 'MarkerSize', 4.5, ...
                 'MarkerFaceColor',[0 0 0], 'MarkerEdgeColor','none', 'HandleVisibility','off');
        end

        % Title (unbolded) with metrics
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
        title(ttlTxt, 'FontSize',9, 'FontWeight','normal');

        ax = gca; ax.FontSize = 8;
        if k < nCh, ax.XTickLabel = []; else, xlabel('ms'); end
        ylabel('\muV');
    end

    sg = sprintf('Event %d  |  align: midpoint  |  display: \\pm%.1f ms  |  metrics: \\pm%.1f ms  |  channels=%d  |  %s', ...
                 e, 1e3*HWdisp/sfx, 1e3*HWmet/sfx, nCh, tagStr);
    sgtitle(tl, sg, 'FontSize',12,'FontWeight','bold');

    outPng = fullfile(saveDir, sprintf('Evt%03d_Stack_ampHW_fixedY_dispHW%ds_metHW%ds.png', ...
        e, HWdisp, HWmet));
    exportgraphics(f, outPng, 'Resolution', 220);
    close(f);
    fprintf('Saved: %s\n', outPng);
end

if nBad>0
    fprintf('Skipped %d event(s) (bad/missing indices/out-of-bounds).\n', nBad);
end
end
