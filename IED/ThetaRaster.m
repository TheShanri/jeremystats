function ThetaRaster(inputFolder, varargin)
% plot_theta_ripple_channels_inverted
% -------------------------------------------------------------------------
% Clean + lean:
% - Blanks ONLY channels 1 and 64 (top/bottom NaN rows)
% - Gaussian smoothing + bicubic upsampling on INTERIOR (channels 2–63)
% - Fixed color scale [-0.2, 0.2]
% - Every channel tick (1–64) visible
% - Axis tightly fits data in X (no empty left/right space)
% - Saves EPS (no SVG)
% - No sloppy chaining; everything spelled out with clear variable names
% -------------------------------------------------------------------------

    fprintf('\n--- Plot Theta/Ripple Heatmap (Tight, Smoothed, EPS) ---\n');
    fprintf('Input folder: %s\n', inputFolder);

    % -------- Simple knobs --------
    gaussianSigma  = 0.75;     % smoothing amount (in pixels)
    upsampleFactor = 3;        % 1=no upsample; 2–4 looks nice
    colormapName   = 'jet';    % try 'turbo' if you prefer
    colorScale     = [-0.2, 0.2];
    titleText      = 'Theta–Ripple Heatmap — Channel 64 at Bottom';

    % -------- Load data (no chaining) --------
    xFile = load(fullfile(inputFolder, 'x1.mat'));
    xFieldNames = fieldnames(xFile);
    xValues = xFile.(xFieldNames{1});
    xValues = xValues(:).';  % force row vector

    yFile = load(fullfile(inputFolder, 'y1.mat'));
    yFieldNames = fieldnames(yFile);
    yValues = yFile.(yFieldNames{1});
    yValues = yValues(:).';  % force row vector

    cFile = load(fullfile(inputFolder, 'c1.mat'));
    cFieldNames = fieldnames(cFile);
    cMatrix = cFile.(cFieldNames{1});

    fprintf('Loaded sizes -> x:%d | y:%d | c:%dx%d\n', ...
        numel(xValues), numel(yValues), size(cMatrix,1), size(cMatrix,2));

    % -------- Ensure orientation: cMatrix is [numel(y) x numel(x)] --------
    expectedRows = numel(yValues);
    expectedCols = numel(xValues);

    if ~isequal(size(cMatrix), [expectedRows, expectedCols])
        if isequal(size(cMatrix), [expectedCols, expectedRows])
            fprintf('Transposing cMatrix to [numel(y) x numel(x)]...\n');
            cMatrix = cMatrix.'; %#ok<UDIM>
        else
            error('Matrix size mismatch: cMatrix must be [%d x %d].', expectedRows, expectedCols);
        end
    end

    % -------- Smooth + upsample INTERIOR (channels 2–63) --------
    fprintf('Smoothing interior with imgaussfilt (sigma=%.3f)...\n', gaussianSigma);
    interiorMatrix = imgaussfilt(cMatrix, gaussianSigma);

    if upsampleFactor > 1
        fprintf('Upsampling interior by x%.1f (bicubic)...\n', upsampleFactor);
        interiorMatrix = imresize(interiorMatrix, upsampleFactor, 'bicubic');
    end

    % -------- Add exactly one NaN row on top (ch1) and bottom (ch64) --------
    fprintf('Adding NaN rows for channel 1 (top) and 64 (bottom)...\n');
    numberOfColumns = size(interiorMatrix, 2);
    nanRow = nan(1, numberOfColumns);
    fullMatrix = [nanRow; interiorMatrix; nanRow];   % only 1 and 64 are blank

    % -------- Build axes --------
    channelNumbers = 1:64;

    % -------- Plot (map image to exact data extents; no X-margin) --------
    fprintf('Plotting with fixed color scale [%g, %g]...\n', colorScale(1), colorScale(2));
    figureHandle = figure('Color','w','Position',[100 100 900 700]);

    % IMPORTANT: use XData/YData as EXTENTS so upsampled size doesn't matter
    xExtent = [xValues(1), xValues(end)];
    yExtent = [channelNumbers(1), channelNumbers(end)];

    imagesc('XData', xExtent, 'YData', yExtent, 'CData', fullMatrix);
    set(gca, 'YDir', 'reverse');     % channel 64 at bottom

    colormap(colormapName);
    caxis(colorScale);
    colorbar;

    xlabel('X');
    ylabel('Channel #');
    title(titleText, 'FontWeight','bold');

    % Every channel labeled
    yticks(channelNumbers);
    yticklabels(string(channelNumbers));
    set(gca, 'FontSize', 8, 'TickDir', 'out', 'LineWidth', 1);
    grid on; box on;

    % Tight to data: exact start/end, no empty left/right
    xlim(xExtent);
    ylim([1 64]);

    drawnow;

    % -------- Save EPS --------
    epsFilePath = fullfile(inputFolder, 'theta_ripple_channels_inverted.eps');
    fprintf('Saving EPS to: %s\n', epsFilePath);
    exportgraphics(figureHandle, epsFilePath, 'ContentType', 'vector', 'BackgroundColor', 'white');

    fprintf('--- Done ---\n\n');
end