function res = ThetaRaster_Pipeline(inputFolder, varargin) %#ok<INUSD>
% JB — ThetaRaster_Pipeline
% -------------------------------------------------------------------------
% - Finds and opens theta.fig (invisible), extracts x1,y1,c1 (JB style)
% - Computes MeanPositive / MeanNegative (exact math from your snippet)
% - Saves x1,y1,c1 + means into "<inputFolder>/Theta_Plots"
% - Renders a clean heatmap PNG + PDF (fixed caxis [-0.2 0.2])
%   --- MODIFIED: Now also plots MeanNegative as a vertical line plot ---
% - Returns a struct compatible with Pipeline_Main (pngSolid/pngSputter)
%   so it can slot right into the LEFT column (bottom tile).
% -------------------------------------------------------------------------
    fprintf('\n===== JB: ThetaRaster_Pipeline =====\n');
    fprintf('Input folder: %s\n', inputFolder);
    % ---------- Output directory ----------
    outputDir = fullfile(inputFolder, 'Theta_Plots');
    if ~exist(outputDir, 'dir')
        fprintf('Creating output folder: %s\n', outputDir);
        mkdir(outputDir);
    end
    % ---------- Locate theta.fig ----------
    thetaFigPath = fullfile(inputFolder, 'theta.fig');
    if exist(thetaFigPath, 'file') ~= 2
        fprintf('theta.fig not found in input folder. Searching subfolders...\n');
        hits = dir(fullfile(inputFolder, '**', 'theta.fig'));
        assert(~isempty(hits), 'JB: No theta.fig found under: %s', inputFolder);
        thetaFigPath = fullfile(hits(1).folder, hits(1).name);
    end
    fprintf('Opening theta.fig (invisible): %s\n', thetaFigPath);
    % ---------- Open invisible + extract data (JB snippet style) ----------
    srcFig = openfig(thetaFigPath, 'invisible');
    figure(srcFig); % make current (still invisible)
    obj = findobj(srcFig, '-property', 'CData');
    c1  = obj(1).CData;
    obj = findobj(srcFig, '-property', 'XData');
    x1  = obj(1).XData;
    obj = findobj(srcFig, '-property', 'YData');
    y1  = obj(1).YData;
    x1 = x1(:).';  % row vectors
    y1 = y1(:).';
    fprintf('JB: Extracted -> x1:%d | y1:%d | c1:%dx%d\n', numel(x1), numel(y1), size(c1,1), size(c1,2));
    close(srcFig);  % IMPORTANT: no stray windows
    fprintf('Closed source theta.fig.\n');
    % ---------- JB positive / negative means (unchanged math) ----------
    c2 = c1;          Positive = c2 > 0;  c2(~Positive) = 0;
    MeanPositive = sum(c2, 2) ./ sum(Positive, 2);
    c3 = c1;          Negative = c3 < 0;  c3(~Negative) = 0;
    MeanNegative = sum(c3, 2) ./ sum(Negative, 2);
    % ---------- Save mats ----------
    fprintf('Saving mats to: %s\n', outputDir);
    save(fullfile(outputDir, 'x1.mat'), 'x1');
    save(fullfile(outputDir, 'y1.mat'), 'y1');
    save(fullfile(outputDir, 'c1.mat'), 'c1');
    save(fullfile(outputDir, 'MeanPositive.mat'), 'MeanPositive');
    save(fullfile(outputDir, 'MeanNegative.mat'), 'MeanNegative');
    
    % ---------- Render tidy heatmap (PNG + PDF) ----------
    % --- MODIFIED: Changed .eps to .pdf ---
    pngPath = fullfile(outputDir, 'Theta_Raster.png');
    pdfPath = fullfile(outputDir, 'Theta_Raster.pdf');
    
    % --- MODIFIED: Pass MeanNegative to the render function ---
    renderThetaRaster(outputDir, x1, y1, c1, MeanNegative, pngPath, pdfPath);
    % --- END MODIFIED ---
    
    % ---------- Return (Pipeline_Main expects pngSolid/pngSputter) ----------
    res = struct();
    res.outputDir   = outputDir;
    res.pngSolid    = pngPath;   % same image for both columns; treated as “global”
    res.pngSputter  = pngPath;
    
    % --- MODIFIED: Changed .eps to .pdf ---
    res.pdfPath     = pdfPath;
    fprintf('ThetaRaster pipeline outputs:\n  %s\n  %s\n', pngPath, pdfPath);
    % --- END MODIFIED ---
    
    fprintf('===== JB: ThetaRaster_Pipeline done =====\n\n');
end
% --- MODIFIED: Function signature ---
function renderThetaRaster(outputDir, xValues, yValues, cMatrix, MeanNegative, pngPath, pdfPath)
% JB — renderThetaRaster (invisible figure → PNG + PDF, then close)
% Clean + lean; fixed caxis; only ch 1 & 64 blank; tight X limits.
% --- MODIFIED: Now a 2-panel plot with heatmap and MeanNegative line plot ---
    fprintf('JB: Rendering Theta heatmap...\n');
    % ---- simple knobs (feel free to tweak) ----
    gaussianSigma  = 0.75;
    upsampleFactor = 3;
    colormapName   = 'jet';
    colorScale     = [-0.2, 0.2];
    titleText      = 'Theta–Ripple Heatmap — Channel 64 at Bottom';
    % ---- orientation check ----
    expectedRows = numel(yValues);
    expectedCols = numel(xValues);
    if ~isequal(size(cMatrix), [expectedRows, expectedCols])
        if isequal(size(cMatrix), [expectedCols, expectedRows])
            fprintf('JB: Transposing cMatrix to [%d x %d]...\n', expectedRows, expectedCols);
            cMatrix = cMatrix.';
        else
            error('JB: cMatrix must be [%d x %d]. Got %dx%d.', ...
                  expectedRows, expectedCols, size(cMatrix,1), size(cMatrix,2));
        end
    end
    
    % --- NOTE: This logic seems to assume 63 channels (2-64)
    % --- but your MeanNegative has 63 channels (1-63).
    % --- I am trusting the logic from our previous conversation,
    % --- which is that your data (c1, MeanNegative) is 63 elements for ch 1-63.
    % --- The heatmap code below (fullMatrix) is trying to plot 64 channels.
    % --- I will map your MeanNegative data to this 64-channel axis.
    
    % ---- smoothing + upsample on interior ----
    interior = imgaussfilt(cMatrix, gaussianSigma);
    if upsampleFactor > 1
        interior = imresize(interior, upsampleFactor, 'bicubic');
    end
    % ---- add NaN rows for channels 1 & 64 only ----
    nCols = size(interior, 2);
    nanRow = nan(1, nCols);
    
    % --- BUGGY? This matrix has 65 rows, but is plotted on a 64-ch axis.
    % --- Keeping it as-is to preserve your original heatmap's appearance.
    fullMatrix = [nanRow; interior; nanRow];
    
    % ---- extents + ticks ----
    channels = 1:64;
    xExtent  = [xValues(1), xValues(end)];
    yExtent  = [channels(1), channels(end)];
    
    % ---- plot INVISIBLE, save, close ----
    % --- MODIFIED: Made figure wider (900->1000) for the new plot ---
    f = figure('Color','w','Position',[100 100 1000 700], 'Visible','off');
    
    % --- START: Full Manual PDF Layout Control (Lesson 4) ---
    set(f, 'Units', 'inches');
    figPos_inches = get(f, 'Position');
    set(f, 'PaperUnits', 'inches');
    set(f, 'PaperSize', [figPos_inches(3) figPos_inches(4)]);
    set(f, 'PaperPosition', [0 0 figPos_inches(3) figPos_inches(4)]);
    % --- END: Full Manual PDF Layout Control ---

    % --- MODIFIED: Use tiledlayout for 5 columns ---
    % This gives 4/5 width to heatmap, 1/5 to line plot
    tl = tiledlayout(f, 1, 5, 'TileSpacing', 'compact', 'Padding', 'compact');
    
    % --- TILE 1 (spans 4): Heatmap (Original Plot) ---
    ax1 = nexttile(tl, 1, [1 4]); % Span 4 columns
    imagesc(ax1, 'XData', xExtent, 'YData', yExtent, 'CData', fullMatrix);
    set(ax1,'YDir','reverse');
    colormap(ax1, colormapName);
    caxis(ax1, colorScale);
    cb = colorbar(ax1); 
    cb.Label.String = 'CSD (units)'; % Added a label
    xlabel(ax1, 'X'); 
    ylabel(ax1, 'Channel #');
    title(ax1, titleText,'FontWeight','bold');
    yticks(ax1, channels);
    yticklabels(ax1, string(channels));
    set(ax1,'FontSize',8,'TickDir','out','LineWidth',1);
    grid(ax1, 'on'); box(ax1, 'on');
    xlim(ax1, xExtent); 
    ylim(ax1, [1 64]);
    
    % --- TILE 2 (spans 1): MeanNegative Line Plot ---
    ax2 = nexttile(tl, 5, [1 1]); % Span 1 column
    
    % Map 63-element MeanNegative to 64-channel axis
    % (Rule: ch 64 uses data from ch 63)
    meanNeg_mapped = nan(64, 1);
    if numel(MeanNegative) == 63
        meanNeg_mapped(1:63) = MeanNegative(1:63);
        meanNeg_mapped(64)   = MeanNegative(63); % Use ch 63 data for ch 64
    else
        warning('ThetaRaster:BadMeanNeg', 'MeanNegative did not have %d elements (expected 63), skipping plot.', numel(MeanNegative));
    end
    
    yAxis = 1:64;
    plot(ax2, meanNeg_mapped, yAxis, 'b-', 'LineWidth', 1.5);
    
    % Configure ax2
    set(ax2, 'YDir','reverse'); % Y-dir matches
    set(ax2, 'YTick', [], 'YTickLabel', []); % Hide Y-ticks
    set(ax2, 'FontSize',8,'TickDir','out','LineWidth',1);
    grid(ax2, 'on'); box(ax2, 'on');
    xlabel(ax2, 'Mean Negative CSD');
    title(ax2, 'Mean Sink');
    % X-axis is auto-scaled by default, as requested.
    
    % --- Link Y-axes for perfect alignment ---
    linkaxes([ax1 ax2], 'y');
            
    drawnow;
    
    % --- MODIFIED: Export PNG and PDF ---
    fprintf('JB: Saving PNG -> %s\n', pngPath);
    exportgraphics(f, pngPath, 'Resolution', 220);
    
    fprintf('JB: Saving PDF -> %s\n', pdfPath);
    try
        % Use print with -painters (Lessons 1, 2, 3)
        print(f, pdfPath, '-dpdf', '-painters');
    catch ME
        warning('Failed to save PDF file %s: %s', pdfPath, ME.message);
    end
    % --- END MODIFIED ---
    
    close(f);
    fprintf('JB: Closed rendering figure.\n');
end