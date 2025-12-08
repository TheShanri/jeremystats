function VoltageRaster_GrandAverage(rootFolder, varargin)
% VoltageRaster_GrandAverage
% Recursively finds 'VoltageRaster_Avg_Values_SOLID.csv' and '...SPUTTER.csv'
% in the given rootFolder, calculates the Grand Average (mean across animals),
% and saves the results (CSV, PNG, PDF) in a 'GrandAverage_Output' folder.
%
% Usage:
%   VoltageRaster_GrandAverage(rootFolder)
%   VoltageRaster_GrandAverage(..., 'climMicroV', 150)
%   VoltageRaster_GrandAverage(..., 'baseOnly', true)
%
% Parameters:
%   rootFolder : String/char path to the top-level directory containing animal subfolders.
%   'climMicroV': (Optional) Manual color limit (±µV). If empty, calculated automatically.
%   'baseOnly'  : (Optional) Logical (default false). If true, reads 'Mice_group.csv' 
%                 in rootFolder and filters folders based on the 'Session' column 
%                 where Group='Base'.

    p = inputParser;
    p.addRequired('rootFolder', @(s) ischar(s) || isstring(s));
    p.addParameter('climMicroV', [], @(x) isempty(x) || (isscalar(x) && x > 0));
    p.addParameter('baseOnly', true, @(x) islogical(x) || isnumeric(x));
    p.parse(rootFolder, varargin{:});
    
    rootFolder = char(p.Results.rootFolder);
    climOpt    = p.Results.climMicroV;
    baseOnly   = logical(p.Results.baseOnly);
    
    % Output Directory
    outDir = fullfile(rootFolder, 'GrandAverage_Output');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    
    fprintf('Starting Grand Average processing in: %s\n', rootFolder);
    fprintf('Output will be saved to: %s\n', outDir);

    % --- Base Only Filtering Setup ---
    baseSessionList = {};
    if baseOnly
        groupFile = fullfile(rootFolder, 'Mice_group.csv');
        if ~isfile(groupFile)
            error('baseOnly=true requested, but Mice_group.csv not found in: %s', rootFolder);
        end
        
        fprintf('Loading group info from: %s\n', groupFile);
        T_grp = readtable(groupFile);
        
        % Normalize variable names to handle case sensitivity
        grpCols = lower(T_grp.Properties.VariableNames);
        
        idxGrp     = find(strcmp(grpCols, 'group'), 1);
        idxSession = find(strcmp(grpCols, 'session'), 1);
        
        if isempty(idxGrp) || isempty(idxSession)
            error('Mice_group.csv must contain "Group" and "Session" columns for specific folder matching.');
        end
        
        % Filter for Base (case-insensitive)
        groups   = T_grp{:, idxGrp};
        sessions = T_grp{:, idxSession};
        
        baseMask = strcmpi(groups, 'base');
        baseSessionList = sessions(baseMask);
        
        % Clean up list
        if ischar(baseSessionList), baseSessionList = {baseSessionList}; end
        baseSessionList = string(baseSessionList);
        baseSessionList = unique(baseSessionList(~ismissing(baseSessionList) & baseSessionList ~= ""));
        
        fprintf('Base-only filtering ENABLED. Found %d Base sessions: %s\n', ...
            numel(baseSessionList), strjoin(baseSessionList, ', '));
            
        if isempty(baseSessionList)
            warning('No sessions found with Group="Base". Output will likely be empty.');
        end
    end

    % --- Process SOLID ---
    processGroup(rootFolder, 'SOLID', outDir, climOpt, baseOnly, baseSessionList);
    
    % --- Process SPUTTER ---
    processGroup(rootFolder, 'SPUTTER', outDir, climOpt, baseOnly, baseSessionList);
    
    fprintf('Done.\n');
end

function processGroup(rootFolder, tag, outDir, climOpt, baseOnly, baseSessionList)
    fileName = sprintf('VoltageRaster_Avg_Values_%s.csv', tag);
    
    % Recursive search for files
    filePattern = fullfile(rootFolder, '**', fileName);
    files = dir(filePattern);
    
    % Remove files that might be inside the output folder itself
    keepMask = true(size(files));
    for i = 1:numel(files)
        if contains(files(i).folder, 'GrandAverage_Output')
            keepMask(i) = false;
        end
    end
    files = files(keepMask);
    
    if isempty(files)
        fprintf('[%s] No CSV files found. Skipping.\n', tag);
        return;
    end
    
    fprintf('[%s] Found %d files. Loading and averaging...\n', tag, numel(files));
    
    % --- Accumulation Variables ---
    sumMat = [];
    count = 0;
    
    % Metadata (captured from first valid file)
    tRelMs = [];
    chLabels = {};
    
    for i = 1:numel(files)
        fPath = fullfile(files(i).folder, files(i).name);
        
        % --- FILTERING STEP ---
        if baseOnly
            % We must ensure the folder path corresponds to a BASE session.
            % Since 'Mouse' ID appears in both Base and CNO folders (e.g., M13_pten),
            % we match against the specific 'Session' identifier (e.g., HF4s2aug1).
            folderPath = string(files(i).folder);
            matchFound = false;
            
            for bs = 1:numel(baseSessionList)
                % Check if the folder path contains the specific Session ID
                if contains(folderPath, baseSessionList(bs), 'IgnoreCase', true)
                    matchFound = true;
                    break;
                end
            end
            
            if ~matchFound
                % Optional: verbose logging
                % fprintf('  [Skip] Non-Base session path: ...%s\n', files(i).folder(max(1,end-30):end));
                continue; 
            end
        end
        
        try
            T = readtable(fPath);
            
            % Basic Validation
            if width(T) < 2
                warning('File %s has insufficient columns. Skipping.', fPath);
                continue;
            end
            
            % Extract numeric data (columns 2 to end)
            % Assuming Column 1 is 'Channel'
            dataCols = T{:, 2:end};
            currLabels = T.Channel;
            
            % Initialize on first valid file
            if isempty(sumMat)
                sumMat = zeros(size(dataCols));
                chLabels = currLabels;
                
                % Parse Time Headers
                hdr = T.Properties.VariableNames(2:end);
                tRelMs = parseTimeHeaders(hdr);
            else
                % Consistency Check
                if ~isequal(size(sumMat), size(dataCols))
                    warning('Dimension mismatch in file %s. Expected %dx%d, got %dx%d. Skipping.', ...
                        fPath, size(sumMat,1), size(sumMat,2), size(dataCols,1), size(dataCols,2));
                    continue;
                end
            end
            
            % Accumulate
            if any(isnan(dataCols(:)))
               dataCols(isnan(dataCols)) = 0; 
            end
            
            sumMat = sumMat + dataCols;
            count = count + 1;
            
        catch ME
            warning('Failed to process %s: %s', fPath, ME.message);
        end
    end
    
    if count == 0
        fprintf('[%s] No valid data accumulated (Filter active: %d).\n', tag, baseOnly);
        return;
    end
    
    % --- Calculate Mean ---
    grandAvg = sumMat / count;
    
    fprintf('[%s] Computed average from %d animals.\n', tag, count);
    
    % --- Save CSV ---
    % Suffix for filename if filtered
    suffix = tag;
    if baseOnly
        suffix = [tag '_BaseOnly'];
    end
    
    outCSV = fullfile(outDir, sprintf('GrandAvg_VoltageRaster_Values_%s.csv', suffix));
    try
        % Reconstruct Table
        T_rows = table(chLabels, 'VariableNames', {'Channel'});
        
        % Re-use original headers if possible, or regenerate
        tHeaders = arrayfun(@(t) sprintf('T_%.2fms', t), tRelMs, 'UniformOutput', false);
        tHeaders = strrep(tHeaders, '.', 'p');
        tHeaders = strrep(tHeaders, '-', 'm');
        
        T_vals = array2table(grandAvg, 'VariableNames', tHeaders);
        T_out = [T_rows, T_vals];
        
        writetable(T_out, outCSV);
        fprintf('[%s] Saved CSV: %s\n', tag, outCSV);
    catch ME
        warning('Failed to write CSV: %s', ME.message);
    end
    
    % --- Plotting ---
    % Determine CLim
    if isempty(climOpt)
        vals = abs(grandAvg(:));
        if isempty(vals)
            clim = 1; 
        else
            clim = prctile(vals, 99.5) * 1.12; % 99.5th percentile + padding
        end
        fprintf('[%s] Auto-calculated CLim: ±%.2f µV\n', tag, clim);
    else
        clim = climOpt;
    end
    
    outPng = fullfile(outDir, sprintf('GrandAvg_Raster_%s.png', suffix));
    outPdf = fullfile(outDir, sprintf('GrandAvg_Raster_%s.pdf', suffix));
    
    renderGrandAvg(grandAvg, tRelMs, chLabels, suffix, outPng, outPdf, clim, count);
end

% ======================================================================
%                             HELPERS
% ======================================================================

function tVals = parseTimeHeaders(headers)
    % Parses headers like 'T_minus20p0ms', 'T_0p0ms', 'T_5p5ms' back to double
    tVals = zeros(1, numel(headers));
    for i = 1:numel(headers)
        h = headers{i};
        % Remove prefix/suffix
        h = strrep(h, 'T_', '');
        h = strrep(h, 'ms', '');
        % Handle signs and decimals
        h = strrep(h, 'minus', '-');
        h = strrep(h, 'm', '-'); % Safety if 'm' used instead of 'minus'
        h = strrep(h, 'p', '.');
        
        val = str2double(h);
        if isnan(val)
            % Fallback: simple index-based or warning
            warning('Could not parse time header: %s', headers{i});
            val = 0; 
        end
        tVals(i) = val;
    end
end

function renderGrandAvg(MU, tRelMs, chLabels, tag, outPng, outPdf, clim, nCount)
    nCh = size(MU, 1);
    
    % Dynamic height based on channel count
    perRowPx = 12; basePx = 260; maxPx = 2600;
    figH = min(maxPx, basePx + perRowPx * nCh);
    
    f = figure('Color','w','Position',[100 100 1100 figH], 'Visible', 'off');
    
    % Layout for PDF
    set(f, 'Units', 'inches');
    figPos_inches = get(f, 'Position');
    set(f, 'PaperUnits', 'inches');
    set(f, 'PaperSize', [figPos_inches(3) figPos_inches(4)]);
    set(f, 'PaperPosition', [0 0 figPos_inches(3) figPos_inches(4)]);
    
    % Plot
    imagesc(tRelMs, 1:nCh, MU);
    set(gca, 'YDir', 'reverse'); 
    caxis([-clim, +clim]);
    colormap(jet); 
    cb = colorbar;
    cb.Label.String = 'Voltage (µV)';
    
    xlabel('Time (ms)');
    
    % Y-Axis Labels
    % Clean up channel labels if they contain excessive text?
    % The labels come from CSV: "row 1 (CSC4)". We use them as is.
    set(gca, 'YTick', 1:nCh, 'YTickLabel', chLabels, 'FontSize', 9, 'TickLabelInterpreter', 'none');
    
    title(sprintf('Grand Avg %s (N = %d animals)', tag, nCount), ...
        'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none');
    
    % Save PNG
    exportgraphics(f, outPng, 'Resolution', 220);
    fprintf('[%s] Saved PNG: %s\n', tag, outPng);
    
    % Save PDF
    try
        print(f, outPdf, '-dpdf', '-painters');
        fprintf('[%s] Saved PDF: %s\n', tag, outPdf);
    catch ME
        warning('Failed to save PDF: %s', ME.message);
    end
    
    close(f);
end