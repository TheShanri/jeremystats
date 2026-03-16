function Extract_First_Combo()
% EXTRACT_FIRST_COMBO (STANDALONE)
% Isolates the first HighTone_LowTone event directly from the .mat file 
% without requiring the external spreadsheet.

    % ---------------- CONFIGURATION ----------------
    matFilePath = 'D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\J2_PRECON2_SP_091325_ForPython.mat';
    outputDir   = 'D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA';
    
    targetEvent = 'HighTone_LowTone';
    eventIdx    = 1; % Force the first occurrence

    fprintf('\n=======================================================\n');
    fprintf('ISOLATING SINGLE COMBO EVENT (NO SPREADSHEET)\n');
    fprintf('   Target: %s (Index: %d)\n', targetEvent, eventIdx);
    fprintf('=======================================================\n');

    % 1. Parse Session Identity
    [~, matName, ~] = fileparts(matFilePath);
    sessionName = strrep(matName, '_ForPython', '');
    fprintf('Session: %s\n', sessionName);

    % 2. Extract Data from HDF5 (.mat)
    fprintf('Extracting signals from .mat file...\n');
    if ~exist(matFilePath, 'file')
        error('File not found: %s', matFilePath);
    end

    try
        fs = double(h5read(matFilePath, '/SessionData/Meta/Fs'));
    catch
        fs = 32000; % Fallback
    end
    
    evtPath = ['/SessionData/' targetEvent];
    try
        evtInfo = h5info(matFilePath, evtPath);
    catch
        error('Dataset %s not found inside %s. Did you run the extraction step?', evtPath, matName);
    end
    
    % Attempt to pull the exact timestamp natively from the .mat file
    evtTimeSec = NaN;
    try
        tsAll = double(h5read(matFilePath, [evtPath '/Timestamps']));
        if numel(tsAll) >= eventIdx
            evtTimeSec = tsAll(eventIdx);
        end
    catch
        % Silently pass and leave as NaN if no Timestamps array exists
    end

    if ~isnan(evtTimeSec)
        fprintf('   > Internal Timestamp Found: %.3f s\n', evtTimeSec);
    else
        fprintf('   > No internal timestamp found. Proceeding with signal extraction.\n');
    end

    allDatasets = {evtInfo.Datasets.Name};
    
    % Filter out non-signal metadata fields (like Timestamps)
    chans = allDatasets(~contains(allDatasets, 'Timestamps', 'IgnoreCase', true));
    chans = chans(~contains(chans, 'TS', 'IgnoreCase', true));

    % Initialize the output structure
    Data = struct();
    Data.Meta.Session = sessionName;
    Data.Meta.Event = targetEvent;
    Data.Meta.EventIndex = eventIdx;
    Data.Meta.Midpoint_Time_Sec = evtTimeSec;
    Data.Meta.Fs = fs;

    for i = 1:numel(chans)
        chName = chans{i};
        M = double(h5read(matFilePath, [evtPath '/' chName]));
        
        % Enforce row orientation [Trials x Samples]
        sz = size(M);
        if numel(sz) ~= 2, M = reshape(M, sz(1), []); end
        if size(M,1) > size(M,2), M = M.'; end
        
        if size(M, 1) < eventIdx
            error('Not enough trials in channel %s to extract index %d.', chName, eventIdx);
        end
        
        % Isolate the single trial
        trace = M(eventIdx, :);
        trace(~isfinite(trace)) = 0; % Clean NaNs
        
        Data.Signals.(chName) = trace;
        fprintf('.');
    end
    fprintf(' Done.\n');

    % 3. Save the new isolated file
    outName = sprintf('%s_FirstHTLT.mat', sessionName);
    fullOut = fullfile(outputDir, outName);
    
    save(fullOut, 'Data', '-v7.3');
    fprintf('\n[SUCCESS] Saved isolated data to:\n%s\n', fullOut);
end