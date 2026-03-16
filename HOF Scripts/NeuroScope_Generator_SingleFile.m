function NeuroScope_Generator_SingleFile(matFilePath, outputFolder, trialMode)
% NEUROSCOPE_GENERATOR_SINGLEFILE (HIGH-RES & IMPROVED WAVEFORMS)
% Processes ONE specific .mat file and adds images to the output folder.
%
% ARGS:
%    matFilePath  : Full path to input .mat file
%    outputFolder : Full path to output folder
%    trialMode    : (Optional) true/false. If true, generates ONLY 1 image.
%
% USAGE: 
%    NeuroScope_Generator_SingleFile('D:\Data\J1_ForPython.mat', 'D:\Data\IMG_FLAT', true)

    % --- ARGUMENT HANDLING -----------------------------------------------
    if nargin < 3
        trialMode = false;
    end
    % --- CONFIGURATION ---------------------------------------------------
    % Visual Config
    WIN_SEC = 5;            % "x5" (Generates +/- 5 second view)
    Y_LIMIT_UV = 2000;      % Waveform Cap
    OUTPUT_DPI = 300;       % Increased resolution for sharper images
    
    % Filters
    FILTERS = struct();
    FILTERS.Raw   = [];
    FILTERS.Delta = [1 4];
    FILTERS.Theta = [4 12];
    FILTERS.Gamma = [30 80];
    
    % Constants
    REGIONS = GetRegionMap(); 
    EVENTS = {'Click','Noise','HighTone','LowTone','PelletDelivery','MagPoke','EndOfBox','Shock'};
    
    % --- VALIDATION ------------------------------------------------------
    fprintf('\n=======================================================\n');
    fprintf('NEUROSCOPE GENERATOR: SINGLE FILE MODE\n');
    if trialMode
        fprintf('   >>> TRIAL MODE ACTIVE (1 Event/1 Region/1 Filter) <<<\n');
    end
    fprintf('=======================================================\n');
    
    if ~exist(matFilePath, 'file')
        error('!!! CRITICAL: Input file not found: %s', matFilePath);
    end
    
    if ~exist(outputFolder, 'dir')
        fprintf('   > Creating output directory: %s\n', outputFolder);
        mkdir(outputFolder);
    end
    
    % --- EXECUTION -------------------------------------------------------
    fprintf('TARGET FILE: %s\n', matFilePath);
    
    [folder, name, ext] = fileparts(matFilePath);
    fileInfo = struct();
    fileInfo.folder = folder;
    fileInfo.name = [name ext];
    try
        tStart = tic;
        process_flat(fileInfo, outputFolder, REGIONS, EVENTS, FILTERS, WIN_SEC, Y_LIMIT_UV, OUTPUT_DPI, trialMode);
        tEnd = toc(tStart);
        fprintf('\n[DONE] Finished processing %s in %.1f seconds.\n', name, tEnd);
    catch ME
        fprintf(2, '\n!!! CRASH !!!\n   Error: %s\n   Line: %d\n', ME.message, ME.stack(1).line);
    end
end

function process_flat(fileInfo, outDir, REGIONS, EVENTS, FILTERS, WIN_SEC, Y_LIMIT_UV, OUTPUT_DPI, trialMode)
    
    % --- TRIAL MODE LIMITERS ---
    if trialMode
        EVENTS = EVENTS(1);        
        REGIONS = REGIONS(1);      
        
        fNames = fieldnames(FILTERS);
        trialFilter = struct();
        trialFilter.(fNames{1}) = FILTERS.(fNames{1}); 
        FILTERS = trialFilter;
        
        fprintf('   [DEBUG] Trial Mode: Limiting to Event="%s", Region="%s", Filter="%s"\n', ...
            EVENTS{1}, REGIONS(1).Name, fNames{1});
    end
    
    % Use a slightly wider figure to accommodate axis labels
    hFig = figure('Visible', 'off', 'Position', [0 0 900 600], 'Color', 'w');
    
    % 1. Parse Filename
    rawName = strrep(fileInfo.name, '_ForPython.mat', '');
    parts = split(rawName, '_');
    
    if length(parts) >= 2
        mouseID = parts{1};      
        sessID  = parts{2};      
        if length(parts) > 2
             sessID = strjoin(parts(2:end), '_');
        end
    else
        mouseID = rawName; 
        sessID = 'Unk';
    end
    
    fprintf('   > Identity Parsed: Mouse=[%s] Session=[%s]\n', mouseID, sessID);
    
    sessionPath = fullfile(fileInfo.folder, fileInfo.name);
    
    % 2. Scan HDF5 Structure
    fprintf('   > Scanning HDF5 Structure... ');
    try
        info = h5info(sessionPath, '/SessionData');
        availEvents = {info.Groups.Name}; 
        fprintf('OK. Found %d event groups.\n', length(availEvents));
    catch
        fprintf('FAILED. Could not read /SessionData.\n');
        close(hFig); return; 
    end
    
    imgCount = 0;
    skipCount = 0;
    
    % 3. Loop Events
    for e = 1:length(EVENTS)
        evtName = EVENTS{e};
        evtPathSearch = ['/SessionData/' evtName];
        
        fprintf('\n   --- EVENT [%d/%d]: %s ---\n', e, length(EVENTS), evtName);
        
        if ~any(strcmp(availEvents, evtPathSearch))
            fprintf('       [MISSING] Event not found in HDF5. Skipping.\n');
            continue; 
        end
        
        evtInfo = h5info(sessionPath, evtPathSearch);
        allChans = {evtInfo.Datasets.Name};
        fprintf('       [DATA] Found %d channels available for this event.\n', length(allChans));
        
        % 4. Loop Regions
        for r = 1:length(REGIONS)
            regName = REGIONS(r).Name;
            
            regFile = regexprep(regName, '\s+', ''); 
            regKey  = strrep(regName, ' ', '_'); 
            
            targetChans = REGIONS(r).Channels;
            stackData = {};
            dataLoaded = false;
            
            % Loop Filters
            fNames = fieldnames(FILTERS);
            for fil = 1:length(fNames)
                filtName = fNames{fil};
                passBand = FILTERS.(filtName);
                lVal = 0; hVal = 0;
                
                % Check if File Exists
                fName = sprintf('%s_%s_x%d_f%s_l%dh%d_%s_%s.png', ...
                    mouseID, sessID, WIN_SEC, filtName, lVal, hVal, evtName, regFile);
                fullOut = fullfile(outDir, fName);
                
                if exist(fullOut, 'file')
                    skipCount = skipCount + 1;
                    continue; 
                end
                
                % LOAD DATA (Lazy - only if needed)
                if ~dataLoaded
                    fprintf('           > Loading HDF5 Data for %s... ', regName);
                    for ch = targetChans
                        chName = sprintf('%s_Ch%02d', regKey, ch);
                        if any(strcmp(allChans, chName))
                            trace = h5read(sessionPath, [evtPathSearch '/' chName]);
                            if size(trace, 1) > size(trace, 2)
                                stackData{end+1} = trace(:, 1); 
                            else
                                stackData{end+1} = trace(1, :); 
                            end
                        end
                    end
                    dataLoaded = true;
                    
                    if isempty(stackData)
                        fprintf('NO DATA FOUND. Skipping Region.\n');
                        break; 
                    else
                        fprintf('Loaded %d traces.\n', length(stackData));
                    end
                end
                
                fprintf('           > Generating: %s (%s)... ', filtName, fName);
                
                % Setup Figure
                clf(hFig);
                numRows = length(stackData);
                t = tiledlayout(hFig, numRows, 1, 'Padding', 'tight', 'TileSpacing', 'tight');
                
                for row = 1:numRows
                    ax = nexttile(t);
                    rawTrace = double(stackData{row});
                    
                    % 1. Filter
                    procTrace = ApplyFilter(rawTrace, 32000, passBand);
                    
                    % 2. FULL RES CWT
                    [cfs, f] = cwt(procTrace, 32000, 'FrequencyLimits', [1 120]);
                    P = log10(abs(cfs)+eps);
                    
                    timeVec = linspace(-30, 30, size(P, 2)); 
                    
                    % --- PLOT LEFT AXIS: LOG SCALOGRAM ---
                    yyaxis(ax, 'left');
                    
                    % Prepare Mesh for Surface Plot (Required for Log Scale)
                    [T, F] = meshgrid(timeVec, f);
                    
                    % Use Surface with flat shading
                    surf(ax, T, F, zeros(size(P)), P, 'EdgeColor', 'none', 'FaceColor', 'interp');
                    view(ax, 2); % Top-down view
                    
                    set(ax, 'YScale', 'log'); 
                    set(ax, 'YDir', 'normal');
                    colormap(ax, jet(256));
                    caxis(ax, [-1 2.5]); 
                    ylim(ax, [1 120]); 
                    set(ax, 'YTick', [1 5 10 30 50 100]); % Useful log ticks
                    
                    if row == numRows
                       ylabel(ax, 'Freq (Hz)');
                    else
                       set(ax, 'YTickLabel', []);
                    end
                    
                    % --- PLOT RIGHT AXIS: VOLTAGE OVERLAY ---
                    yyaxis(ax, 'right');
                    tFull = linspace(-30, 30, length(procTrace));
                    
                    % Ensure dsVis isn't too small for very short traces
                    dsVis = max(1, floor(length(procTrace)/10000)); 
                    
                    % UPDATED WAVEFORM STYLING: Thinner lines for crisper outline
                    % 1. Background (Black Outline)
                    plot(ax, tFull(1:dsVis:end), procTrace(1:dsVis:end), 'k', 'LineWidth', 1.2);
                    hold(ax, 'on');
                    % 2. Foreground (White Line)
                    plot(ax, tFull(1:dsVis:end), procTrace(1:dsVis:end), 'w', 'LineWidth', 0.6);
                    
                    ylim(ax, [-Y_LIMIT_UV Y_LIMIT_UV]);
                    xlim(ax, [-WIN_SEC WIN_SEC]); 
                    
                    % Keep Y-Axis Visible
                    set(ax, 'YColor', 'k'); 
                    if row == numRows
                        set(ax, 'XTick', [-WIN_SEC 0 WIN_SEC], ...
                            'XTickLabel', {sprintf('-%d',WIN_SEC),'0',sprintf('+%d',WIN_SEC)});
                        xlabel(ax, 'Time (s)');
                        ylabel(ax, 'Voltage (\muV)');
                    else
                         set(ax, 'XTick', []);
                         set(ax, 'YTickLabel', []); % Hide numbers, keep ticks
                    end
                    
                    % Channel Label Overlay
                    text(ax, 0.01, 0.9, sprintf('Ch %d', targetChans(row)), 'Units', 'normalized', ...
                        'Color', 'w', 'FontSize', 8, 'FontWeight', 'bold', 'BackgroundColor', 'k');
                end
                
                % UPDATED DPI SETTING
                exportgraphics(hFig, fullOut, 'Resolution', OUTPUT_DPI);
                fprintf('Done.\n');
                imgCount = imgCount + 1;
                
            end % End Filter Loop
        end % End Region Loop
    end % End Event Loop
    
    close(hFig);
    fprintf('\n-------------------------------------------------------\n');
    fprintf('SESSION COMPLETE: %s\n', sessionPath);
    fprintf('   > New Images Created: %d\n', imgCount);
    fprintf('   > Skipped (Existed):  %d\n', skipCount);
    if trialMode, fprintf('   > TRIAL MODE ENDED.\n'); end
    fprintf('-------------------------------------------------------\n');
end

function data = ApplyFilter(data, fs, band)
    if isempty(band), return; end 
    [b, a] = butter(3, band/(fs/2), 'bandpass');
    data = filtfilt(b, a, data);
end

function regionMap = GetRegionMap()
    regionMap = struct();
    regionMap(1).Name = 'Left POR';   regionMap(1).Channels = 1:4;
    regionMap(2).Name = 'Left PER';   regionMap(2).Channels = 5:8;
    regionMap(3).Name = 'Right PER';  regionMap(3).Channels = 9:12;
    regionMap(4).Name = 'Right POR';  regionMap(4).Channels = 13:16;
    regionMap(5).Name = 'Right OFC';  regionMap(5).Channels = 17:18;
    regionMap(6).Name = 'Right ACC';  regionMap(6).Channels = 19:20;
    regionMap(7).Name = 'Left ACC';   regionMap(7).Channels = 21:22;
    regionMap(8).Name = 'Left OFC';   regionMap(8).Channels = 23:24;
    regionMap(9).Name = 'Left DHC';   regionMap(9).Channels = 25:26;
    regionMap(10).Name = 'Left RSC';  regionMap(10).Channels = 27:28;
    regionMap(11).Name = 'Right RSC'; regionMap(11).Channels = 29:30;
    regionMap(12).Name = 'Right DHC'; regionMap(12).Channels = 31:32;
end