function out = Scalogram_Waveform_Stacked_ThirdEvent_Pipeline(inputFolder, dataMatPath, varargin)
% Scalogram_Waveform_Stacked_ThirdEvent_Pipeline
% --- CWT (WAVELET) VERSION ---
% - Uses the 3rd event from SOLID and SPUTTER (if present)
% --- MODIFIED: If 3rd event not present, defaults to 1st event ---
% - Picks 4 evenly spaced channels (prefers even rows), or from 'channelIndices' if provided
% - Aligns on last-selected channel positive peak within ±anchorHalfWidthMs of midpoint
% - Window: ±100 ms around anchor
% - For each selected channel: waveform (global µV y-limit) ABOVE its scalogram
% - Scalogram is CWT (Morlet), plotted on log-frequency axis
% - Scalogram x-axis is exactly [-100, +100] ms with ticks at [-100 0 100]
% - Every scalogram shows "Hz" on the y-axis
%
% OUTPUT: PNG(s)/PDF(s) under "<inputFolder>/Spectrogram Waveform Stacked Output/{Solid,Sputter}"
%
% Returns struct OUT with fields:
%   pngSolid, pngSputter, pdfSolid, pdfSputter, statsCSV (unused -> "")
%
% --- NEW ANCHOR PARAMETERS ---
%   'anchorMidpoint' (false): If true, skips peak search and uses the
%                             event's midpoint as the anchor.
%   'anchorChannel'  (0):     Matrix row to use for anchor search.
%                             If 0, defaults to last *selected* channel.
%   'anchorPolarity' ('pos'): Type of peak to find: 'pos', 'neg', or 'abs'.
% -----------------------------

% ---------- Args ----------
p = inputParser;
p.addRequired('inputFolder', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));
p.addParameter('excelPath', "", @(s)ischar(s)||isstring(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('preferEvenRows', true, @(x)islogical(x)||ismember(x,[0 1]));
% Scaling
p.addParameter('scaleToMicroV', 1, @(x) isnumeric(x) && all(isfinite(x)) && all(x>0));
% Alignment
p.addParameter('anchorHalfWidthMs', 5e-3, @(x)isfinite(x)&&x>0);

% --- NEW ANCHOR PARAMETERS ---
p.addParameter('anchorMidpoint', false, @(x)islogical(x)||ismember(x,[0 1]));
p.addParameter('anchorChannel', 0, @(x)isscalar(x)&&isnumeric(x)&&x>=0);
p.addParameter('anchorPolarity', 'pos', @(s) any(validatestring(s, {'pos','neg','abs'})));
% --- END NEW PARAMETERS ---

% --- CWT PARAMETERS (Spectrogram params removed) ---
p.addParameter('fMinHz',      10,   @(x)isfinite(x)&&x>0);   % 10..1000 Hz shown
p.addParameter('fMaxHz',      1000, @(x)isfinite(x)&&x>0);   % 10..1000 Hz shown
% --- END CWT PARAMETERS ---

% Global waveform y-scale
p.addParameter('yLimMicroV', [],   @(x) isempty(x) || (isscalar(x) && x>0));
p.addParameter('yRobustPct', 99.5, @(x) isfinite(x) && x>0 && x<100);
p.addParameter('yPadFrac',   0.12, @(x) isfinite(x) && x>=0 && x<=0.5);
% Scalogram color scaling (log10(magnitude))
p.addParameter('climUpperPct',  99.5, @(x)isfinite(x)&&x>0&&x<100);
p.addParameter('climDynRange',  4,    @(x)isfinite(x)&&x>0); % 4 orders of magnitude (log10 scale)
% Export controls
p.addParameter('maxFigHeightPx', 16000, @(x)isfinite(x)&&x>1000);
p.addParameter('dpi',            220,   @(x)isfinite(x)&&x>=72);
p.parse(inputFolder, dataMatPath, varargin{:});
inputFolder     = string(p.Results.inputFolder);
dataMatPath     = string(p.Results.dataMatPath);
excelPath       = string(p.Results.excelPath);
chUser          = p.Results.channelIndices;
preferEven      = p.Results.preferEvenRows;
scaleToMicroV   = p.Results.scaleToMicroV;
anchorHWms      = p.Results.anchorHalfWidthMs;

% --- NEW ANCHOR PARAMETERS ---
anchorMidpoint = p.Results.anchorMidpoint;
anchorChannel  = p.Results.anchorChannel;
anchorPolarity = p.Results.anchorPolarity;
% --- END NEW PARAMETERS ---

% --- CWT PARAMETERS ---
fMinHz          = p.Results.fMinHz;
fMaxHz          = p.Results.fMaxHz;
% --- END CWT PARAMETERS ---

yLimMicroV      = p.Results.yLimMicroV;
yRobustPct      = p.Results.yRobustPct;
yPadFrac        = p.Results.yPadFrac;
climUpperPct    = p.Results.climUpperPct;
climDynRange    = p.Results.climDynRange;
maxFigH         = p.Results.maxFigHeightPx;
dpi             = p.Results.dpi;

% --- MODIFIED: Added PDF fields ---
out = struct('pngSolid',"", 'pngSputter',"", 'pdfSolid',"", 'pdfSputter',"", 'statsCSV',"");
% --- END MODIFIED ---

% ---------- Layout ----------
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
% --- Output directory name is unchanged for compatibility ---
outRoot = fullfile(inputFolder, "Spectrogram Waveform Stacked Output");
outSOL  = fullfile(outRoot, "Solid");
outSPU  = fullfile(outRoot, "Sputter");
if ~exist(outRoot,'dir'), mkdir(outRoot); end
if ~exist(outSOL,'dir'),  mkdir(outSOL);  end
if ~exist(outSPU,'dir'),  mkdir(outSPU);  end
% ---------- Data ----------
assert(isfile(dataMatPath), 'Data MAT not found: %s', dataMatPath);
mf = matfile(dataMatPath);
try sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRowsAll = size(mf,'d',1);
nSamp    = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end %#ok<NASGU>
% Scaling vector
if numel(scaleToMicroV)==1
    scaleVec = repmat(scaleToMicroV, nRowsAll, 1);
else
    assert(numel(scaleToMicroV) >= nRowsAll, 'scaleToMicroV must be scalar or length >= nRowsAll.');
    scaleVec = scaleToMicroV(:);
end
% ---------- Excel on/off ----------
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
    assert(width(T) >= 2, 'Excel must have [on_samp, off_samp] or [on_sec, off_sec].');
    onSamp  = double(T{:,1});
    offSamp = double(T{:,2});
end
onSamp  = max(1, min(onSamp,  nSamp));
offSamp = max(1, min(offSamp, nSamp));
NrowsXL = numel(onSamp);
% ---------- Events from PNG names ----------
evtSOL = parseEvtNumsFromPngs(solidDir);
evtSPU = parseEvtNumsFromPngs(sputterDir);
fprintf('Found %d SOLID, %d SPUTTER (by filenames). Using the 3rd of each if present.\n', numel(evtSOL), numel(evtSPU));
% ---------- Channel selection (flexible & even-aware) ----------
if ~isempty(chUser)
    chBase = chUser(:).';
    chBase = chBase(chBase>=1 & chBase<=nRowsAll);
else
    chBase = 1:nRowsAll;
    if preferEven
        evens = chBase(mod(chBase,2)==0);
        if ~isempty(evens), chBase = evens; end
    end
end
% Pick 4 evenly spaced channels
if numel(chBase) >= 4
    idxPick = round(linspace(1, numel(chBase), 4));
    chSel   = unique(chBase(idxPick), 'stable');
elseif ~isempty(chBase)
    chSel = unique(chBase, 'stable');
else
    error('No valid channels to select from.');
end
nCh = numel(chSel);
fprintf('Selected %d channels for Scalogram: %s\n', nCh, mat2str(chSel));

% ---------- Render 3rd event (or 1st) of each group ----------
% --- MODIFIED: Default to 1st event if 3rd is not available ---
if numel(evtSOL) >= 3
    % Has 3 or more, use the 3rd
    fprintf('SOLID: Found %d events, using 3rd event (Evt %d).\n', numel(evtSOL), evtSOL(3));
    [out.pngSolid, out.pdfSolid] = renderOne(evtSOL(3), 'SOLID', outSOL, chSel);
elseif numel(evtSOL) >= 1
    % Has 1 or 2, use the 1st
    warning('SOLID: Found only %d events (fewer than 3). Defaulting to 1st event (Evt %d).', numel(evtSOL), evtSOL(1));
    [out.pngSolid, out.pdfSolid] = renderOne(evtSOL(1), 'SOLID', outSOL, chSel);
else
    % Has 0
    warning('SOLID: No events found — skipping scalogram.');
end

if numel(evtSPU) >= 3
    % Has 3 or more, use the 3rd
    fprintf('SPUTTER: Found %d events, using 3rd event (Evt %d).\n', numel(evtSPU), evtSPU(3));
    [out.pngSputter, out.pdfSputter] = renderOne(evtSPU(3), 'SPUTTER', outSPU, chSel);
elseif numel(evtSPU) >= 1
    % Has 1 or 2, use the 1st
    warning('SPUTTER: Found only %d events (fewer than 3). Defaulting to 1st event (Evt %d).', numel(evtSPU), evtSPU(1));
    [out.pngSputter, out.pdfSputter] = renderOne(evtSPU(1), 'SPUTTER', outSPU, chSel);
else
    % Has 0
    warning('SPUTTER: No events found — skipping scalogram.');
end
% --- END MODIFIED ---

fprintf('Scalogram_Waveform_Stacked_ThirdEvent pipeline done.\n');

% ======================================================================
%                              NESTED: RENDER
% ======================================================================
    % --- MODIFIED: Function signature ---
    function [outPng, outPdf] = renderOne(e, tag, outDir, chSel)
        outPng = "";
        outPdf = "";
        % --- Window: ±100 ms ---
        HW = max(1, round(0.100 * sfx));
        tRelMs = (-HW:HW) / sfx * 1e3;
        
        % --- Check event bounds ---
        if e < 1 || e > NrowsXL, warning('%s Evt %d: out of range.', tag, e); return; end
        s0_ev = round(onSamp(e)); s1_ev = round(offSamp(e));
        if ~(isfinite(s0_ev) && isfinite(s1_ev) && s1_ev > s0_ev)
            warning('%s Evt %d: bad on/off.', tag, e); return;
        end
        
        HWanchor = max(1, round(anchorHWms * sfx));
        ancMid = round((s0_ev + s1_ev)/2);
        
        anchorDesc = ""; % For sgtitle
        
        % --- MODIFIED ANCHOR LOGIC ---
        if anchorMidpoint == true
            % Option 1: Use midpoint, skip search
            anchor = ancMid;
            anchorDesc = "Event Midpoint";
        else
            % Option 2: Perform peak-finding search
            
            % Determine reference channel
            if anchorChannel == 0
                refCh = chSel(end); % Default: last *selected* channel
            else
                % Use user-specified channel, with validation
                if anchorChannel < 1 || anchorChannel > nRowsAll || ~any(chSel == anchorChannel)
                    warning('Invalid or unselected anchorChannel %d. Reverting to last selected channel (%d).', anchorChannel, chSel(end));
                    refCh = chSel(end);
                else
                    refCh = anchorChannel; % Use specified, valid row
                end
            end
            
            anchorDesc = sprintf("%s peak on row %d (±%.1f ms)", ...
                                 anchorPolarity, refCh, 1e3*anchorHWms);
            
            % Define search window
            s0a = max(1, ancMid - HWanchor);
            s1a = min(nSamp, ancMid + HWanchor);
            
            % Get data from reference channel
            scRef = scaleVec(refCh);
            y0 = double(mf.d(refCh, s0a:s1a)) * scRef;
            
            if isempty(y0) || all(~isfinite(y0))
                warning('%s Evt %d: no finite data for anchor.', tag, e); return;
            end
            
            % Find peak based on polarity
            switch anchorPolarity
                case 'pos'
                    [~, k_rel] = max(y0);
                case 'neg'
                    [~, k_rel] = min(y0);
                case 'abs'
                    [~, k_rel] = max(abs(y0));
                otherwise
                    [~, k_rel] = max(y0); % Default to pos
            end
            
            anchor = s0a + k_rel - 1;
        end
        
        fprintf('%s Evt %d: Align: %s\n', tag, e, anchorDesc);
        % --- END MODIFIED ANCHOR LOGIC ---
        
        s0 = anchor - HW; s1 = anchor + HW;
        if s0 < 1 || s1 > nSamp
            warning('%s Evt %d: window out of bounds.', tag, e); return;
        end
        
        % --- Collect waveforms for GLOBAL y-limits ---
        rob = 0;
        for ci = 1:nCh
            ch = chSel(ci);
            sc = scaleVec(ch);
            y  = double(mf.d(ch, s0:s1)) * sc;
            yy = y(isfinite(y));
            if isempty(yy), continue; end
            pval = prctile(abs(yy), yRobustPct);
            if isfinite(pval) && pval > rob, rob = pval; end
        end
        if isempty(yLimMicroV)
            yMax = (1 + yPadFrac) * max(1, rob);
        else
            yMax = yLimMicroV;
        end
        yL_global = [-yMax, +yMax];
        
        % --- CWT params ---
        fMax = min(fMaxHz, sfx/2);
        fMin = max(fMinHz, 0.1); % Ensure positive fMin
        if fMin >= fMax, fMin = fMax/100; end
        
        % --- Precompute CWT & CLim across selected channels ---
        allP = [];
        Pane = cell(nCh,1);
        for ci = 1:nCh
            ch = chSel(ci);
            sc = scaleVec(ch);
            y  = double(mf.d(ch, s0:s1)) * sc;
            y(~isfinite(y)) = 0;
            
            % --- CWT CALCULATION ---
            % Compute CWT only within the frequency limits
            [C, F] = cwt(y, sfx, 'FrequencyLimits', [fMin fMax]);
            % Get log-magnitude (plot log10(abs(C)))
            P = log10(abs(C) + eps);
            % --- END CWT CALCULATION ---
            
            % Time vector is just the relative window time
            Tms = tRelMs; 
            
            Pane{ci} = struct('y',y, 'Tms',Tms, 'F',F, 'P',P);
            allP = [allP; P(:)]; %#ok<AGROW>
        end
        allP = allP(isfinite(allP));
        if isempty(allP), pHi = 0; else, pHi = prctile(allP, climUpperPct); end
        pLo = pHi - climDynRange;
        
        % ---------- Figure ----------
        rowsPerChan = 2;                 % waveform + scalogram
        rowsTotal   = rowsPerChan * nCh;
        perRowPx   = 130;
        figW       = 1000;
        topBotPad  = 320;
        figH_full  = topBotPad + perRowPx*rowsTotal;
        figH       = min(figH_full, maxFigH);
        if ~exist(outDir,'dir'), mkdir(outDir); end
        % --- Base name unchanged for compatibility ---
        baseName = sprintf('Evt%03d_SpecWave_Stacked', e); 
        % Labels for channels
        if ~isempty(kept_channels)
            chanLabelAll = arrayfun(@(kk) sprintf('row %d (CSC%d)', chSel(kk), kept_channels(chSel(kk))), 1:nCh, 'UniformOutput', false);
        else
            chanLabelAll = arrayfun(@(kk) sprintf('row %d', chSel(kk)), 1:nCh, 'UniformOutput', false);
        end
        % Single figure expected (4 channels → no chunking)
        f = figure('Color','w','Visible','off','Units','pixels', ...
                   'Position',[60 60 figW figH], 'Renderer','opengl', ...
                   'InvertHardcopy','off');
        
        % --- START: Full Manual PDF Layout Control (Lesson 4) ---
        set(f, 'Units', 'inches');
        figPos_inches = get(f, 'Position');
        set(f, 'PaperUnits', 'inches');
        set(f, 'PaperSize', [figPos_inches(3) figPos_inches(4)]);
        set(f, 'PaperPosition', [0 0 figPos_inches(3) figPos_inches(4)]);
        % --- END: Full Manual PDF Layout Control ---
        
        tl = tiledlayout(f, rowsTotal, 1, 'Padding','loose','TileSpacing','compact');
        for ci = 1:nCh
            D  = Pane{ci};
            % Waveform
            ax1 = nexttile(tl);
            hold(ax1,'on'); box(ax1,'on'); grid(ax1,'on');
            plot(ax1, tRelMs, D.y, 'Color',[0.85 0.10 0.10], 'LineWidth',1.6);
            xline(ax1,0,'--k','LineWidth',0.9);
            yline(ax1,0,':','Color',[0.7 0.7 0.7]);
            ylim(ax1, yL_global);
            xlim(ax1, [-100 100]); xticks(ax1, [-100 0 100]);
            ax1.TickDir = 'out'; ax1.FontSize = 9;
            ax1.XTickLabel = [];               % hide to let scalogram carry the ms labels
            ylabel(ax1, '\muV');
            title(ax1, sprintf('%s — waveform', chanLabelAll{ci}), 'FontSize',9, 'FontWeight','normal');
            
            % --- SCALOGRAM (CWT) PLOT ---
            ax2 = nexttile(tl);
            
            % --- MODIFIED: Reverted to imagesc ---
            imagesc(ax2, D.Tms, D.F, D.P);
            % --- END MODIFIED ---

            axis(ax2,'xy');
            
            colormap(ax2, plasma);
            ax2.YScale = 'log';   % <-- Log scale
            caxis(ax2, [pLo pHi]);
            xline(ax2,0,'--k','LineWidth',0.9,'Color',[0 0 0 0.6]);
            
            % --- MODIFIED: Removed manual ylim to let imagesc auto-size ---
            % This will prevent the clipping that causes the white gap.
            % ylim(ax2, [fMin fMax]); % <-- REMOVED
            
            % --- MODIFIED: Set clean, minimal Y-ticks ---
            baseTicks = [10, 100, 1000];
            ticks = baseTicks(baseTicks >= fMin & baseTicks <= fMax);
            ticks = unique([fMin, ticks, fMax]);
            ticks = ticks(ticks >= fMin & ticks <= fMax);
            
            ax2.YTick = ticks;
            % --- END MODIFIED ---
            
            xlim(ax2, [-100 100]); % Set X-limits
            xticks(ax2, [-100 0 100]);
            ax2.TickDir = 'out'; ax2.FontSize = 9;
            ylabel(ax2, 'Hz');
            if ci == nCh, xlabel(ax2,'Time (ms)'); else, ax2.XTickLabel = []; end
            
            title(ax2, sprintf('%s — scalogram (%.0f–%.0f Hz)', chanLabelAll{ci}, fMin, fMax), 'FontSize',9, 'FontWeight','normal');
        end
        % One colorbar is enough (right side)
        cb = colorbar('eastoutside');
        cb.Label.String = sprintf('Log Magnitude | CLim [%.1f, %.1f]', pLo, pHi);
        
        % --- MODIFIED SGTITLE (STFT info removed) ---
        sg = sprintf('%s | %s | align: %s | Window: \\pm100 ms | CWT (Morlet) | chans=%s', ...
                     tag, baseName, anchorDesc, mat2str(chSel));
        sgtitle(tl, sg, 'FontSize',10, 'FontWeight','bold');
        
        % --- MODIFIED: Export PNG and PDF ---
        drawnow;
        
        % Define paths
        outPng = fullfile(outDir, baseName + ".png");
        outPdf = fullfile(outDir, baseName + ".pdf");
        
        % Save PNG
        exportgraphics(f, outPng, 'Resolution', dpi, 'BackgroundColor','white', 'ContentType','image');
        fprintf('Saved %s (PNG): %s\n', tag, outPng);
        
        % Save PDF (Lessons 1, 2, 3)
        try
            print(f, outPdf, '-dpdf', '-painters');
            fprintf('Saved %s (PDF): %s\n', tag, outPdf);
        catch ME
            warning('Failed to save PDF file %s: %s', outPdf, ME.message);
            outPdf = ''; % Return empty string if failed
        end
        
        close(f);
        % --- END MODIFIED ---
    end
end
% ======================================================================
%                              HELPERS
% ======================================================================
function evts = parseEvtNumsFromPngs(dirpath)
L = dir(fullfile(dirpath, '*.png'));
evts = [];
for k = 1:numel(L)
    m = regexp(L(k).name, 'Evt(\d+)', 'tokens', 'once');
    if ~isempty(m)
        ev = str2double(m{1});
        if isfinite(ev), evts(end+1) = ev; end %#ok<AGROW>
    end
end
evts = sort(unique(evts));
end