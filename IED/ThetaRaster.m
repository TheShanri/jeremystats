function ThetaRaster(inputFolder, varargin)
% plot_theta_ripple_channels_inverted
% -------------------------------------------------------------------------
% Loads x1.mat (1xN), y1.mat (1xM), c1.mat (MxN)
% Blanks ONLY channels 1 and 64
% Smooths + upsamples for a clean look
% Shows all channel labels (1–64)
% Fixes color scale to [-0.2, 0.2]
% Tightens x-axis so it starts and ends exactly at data edges
% Saves EPS (no SVG)
% -------------------------------------------------------------------------

    fprintf('\n--- Plot Theta/Ripple Heatmap (Smoothed, EPS, tight X) ---\n');
    fprintf('Input folder: %s\n', inputFolder);

    % ---------- Simple options ----------
    parser = inputParser;
    addParameter(parser, 'enableSmoothing', true);
    addParameter(parser, 'gaussianSigma', 0.75);
    addParameter(parser, 'upsampleFactor', 3);
    addParameter(parser, 'colormapName', 'jet');
    addParameter(parser, 'titleText', 'Theta–Ripple Heatmap — Channel 64 at Bottom');
    parse(parser, varargin{:});

    enableSmoothing = logical(parser.Results.enableSmoothing);
    gaussianSigma   = parser.Results.gaussianSigma;
    upsampleFactor  = parser.Results.upsampleFactor;
    colormapName    = char(parser.Results.colormapName);
    titleText       = char(parser.Results.titleText);

    % ---------- Load data ----------
    xStruct = load(fullfile(inputFolder, 'x1.mat'));  
    yStruct = load(fullfile(inputFolder, 'y1.mat'));  
    cStruct = load(fullfile(inputFolder, 'c1.mat'));  
    xValues = xStruct.(fieldnames(xStruct){1});
    yValues = yStruct.(fieldnames(yStruct){1});
    cMatrix = cStruct.(fieldnames(cStruct){1});

    % Ensure row vectors
    xValues = xValues(:).';
    yValues = yValues(:).';

    % Fix matrix orientation if needed
    if ~isequal(size(cMatrix), [numel(yValues), numel(xValues)])
        if isequal(size(cMatrix), [numel(xValues), numel(yValues)])
            cMatrix = cMatrix.';
        else
            error('Matrix size mismatch.');
        end
    end

    % ---------- Smooth + upsample interior (channels 2–63) ----------
    interiorMatrix = cMatrix;

    if enableSmoothing
        fprintf('Applying Gaussian smoothing (σ=%.3f)...\n', gaussianSigma);
        interiorMatrix = imgaussfilt(interiorMatrix, gaussianSigma);
    end
    if upsampleFactor > 1
        fprintf('Upsampling %.1fx (bicubic)...\n', upsampleFactor);
        interiorMatrix = imresize(interiorMatrix, upsampleFactor, 'bicubic');
    end

    % ---------- Add NaN rows for channel 1 + 64 ----------
    nanRow = nan(1, size(interiorMatrix, 2));
    fullMatrix = [nanRow; interiorMatrix; nanRow];

    % ---------- Plot ----------
    fprintf('Plotting with fixed color scale [-0.2, 0.2]...\n');
    figure('Color','w','Position',[100 100 900 700]);
    imagesc(xValues, 1:64, fullMatrix);
    set(gca,'YDir','reverse');   % 64 at bottom
    xlabel('X','FontSize',12);
    ylabel('Channel #','FontSize',11);
    title(titleText,'FontSize',14,'FontWeight','bold');
    colormap(colormapName);
    colorbar;
    caxis([-0.2 0.2]);
    yticks(1:64);
    yticklabels(string(1:64));
    set(gca,'FontSize',8,'TickDir','out','LineWidth',1);
    grid on; box on;

    % ---------- Tighten x-axis ----------
    axis tight;  % trims whitespace exactly to data edges
    xlim([xValues(1) xValues(end)]);  % ensures x starts/ends with data

    % ---------- Save EPS ----------
    epsFilePath = fullfile(inputFolder, 'theta_ripple_channels_inverted.eps');
    fprintf('Saving EPS to: %s\n', epsFilePath);
    exportgraphics(gcf, epsFilePath, 'ContentType','vector','BackgroundColor','white');

    fprintf('--- Done ---\n\n');
end
