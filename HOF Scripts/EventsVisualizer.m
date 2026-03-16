function EventsVisualizer(sessionPath, outputDir, trialMode)
% EVENTSVISUALIZER_NO_AVG
% - Saves EVERY channel individually (e.g. Left_POR_Ch01)
% - No Averaging
% - Includes Signal Flip & uV Conversion
%
% USAGE: EventsVisualizer(sessionPath, outputDir, trialMode)

    % --- DEFAULT ARGUMENTS ---
    if nargin < 3, trialMode = false; end

    % --- CONFIGURATION ---------------------------------------------------
    USE_NATIVE_FS = true;   
    TARGET_FS_DEFAULT = 1000; 
    WIN_PRE   = 20.0;       % 20s Before
    WIN_POST  = 20.0;       % 20s After
    
    % --- SIGNAL CONDITIONING ---
    INVERT_SIGNAL = true;   % Multiply by -1
    CONVERT_TO_UV = true;   % Multiply by 1e6
    
    % --- UPDATED EVENT DICTIONARY ---
    EventDict = containers.Map('KeyType','double','ValueType','char');
    EventDict(124) = 'Click';
    EventDict(122) = 'Noise';
    EventDict(118) = 'HighTone';
    EventDict(110) = 'LowTone';
    EventDict(62)  = 'MagPoke';

    fprintf('\n================================================================\n');
    fprintf('EVENTS VISUALIZER: INDIVIDUAL CHANNELS (NO AVG)\n');
    fprintf('----------------------------------------------------------------\n');
    fprintf('Signal: Raw * ADBitVolts');
    if CONVERT_TO_UV, fprintf(' * 1e6 (uV)'); end
    if INVERT_SIGNAL, fprintf(' * -1 (Invert)'); end
    fprintf('\n================================================================\n\n');

    % --- STAGE 0: PATH SETUP ---------------------------------------------
    scriptPath = fileparts(mfilename('fullpath'));
    reqsFolder = fullfile(scriptPath, 'reqsPath');
    
    if exist(reqsFolder, 'dir')
        addpath(reqsFolder);
    end
    
    if isempty(which('Nlx2MatCSC'))
        fprintf(2, '!!! CRITICAL: "Nlx2MatCSC" not found. Check "reqsPath".\n');
    end

    % --- STAGE 1: INPUT VALIDATION ---------------------------------------
    sessionPath = char(sessionPath);
    outputDir   = char(outputDir);
    
    if ~exist(sessionPath, 'dir')
        error('CRITICAL: Session directory does not exist:\n%s', sessionPath);
    end
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end
    
    [~, sessionName] = fileparts(sessionPath);
    if isempty(sessionName), [~, sessionName] = fileparts(fileparts(sessionPath)); end

    % --- STAGE 2: EXECUTE ------------------------------------------------
    try
        ProcessSessionCore(sessionPath, sessionName, outputDir, EventDict, ...
                           USE_NATIVE_FS, TARGET_FS_DEFAULT, WIN_PRE, WIN_POST, ...
                           trialMode, INVERT_SIGNAL, CONVERT_TO_UV);
    catch ME
        fprintf(2, '\n!!! CRASH DURING PROCESSING !!!\n');
        fprintf(2, 'Error: %s\n', ME.message);
        for s = 1:length(ME.stack)
            fprintf(2, '   > In %s (Line %d)\n', ME.stack(s).name, ME.stack(s).line);
        end
    end
    
    fprintf('\n================================================================\n');
    fprintf('JOB COMPLETE.\n');
    fprintf('================================================================\n');
end

function ProcessSessionCore(sessionPath, sessionName, outputDir, EventDict, useNativeFs, defaultFs, winPre, winPost, isTrial, doInvert, doMicroVolts)
    
    dataFolder = fullfile(sessionPath, 'DATA');
    if ~exist(dataFolder, 'dir')
        if exist(fullfile(sessionPath, 'Events.nev'), 'file')
            dataFolder = sessionPath;
        else
            fprintf('   > [ERROR] No DATA folder or Events.nev found.\n');
            return;
        end
    end

    fprintf('[STAGE 2] Scanning Data Folder: %s\n', dataFolder);
    nevFile = fullfile(dataFolder, 'Events.nev');
    
    fprintf('   > Parsing Events.nev...\n');
    Events = ManualEventLoad(nevFile); 
    
    if isempty(Events) || isempty(Events.TTLs)
        fprintf('   > [STOP] No events found.\n');
        return;
    end
    
    validKeys = cell2mat(keys(EventDict));
    ttlDouble = double(Events.TTLs);
    mask = ismember(ttlDouble, validKeys);
    relevantTTLs = ttlDouble(mask);
    relevantTS   = Events.TimeStamps(mask);
    
    if isempty(relevantTTLs)
        fprintf('   > [STOP] No matching event codes.\n');
        return;
    else
        fprintf('   > Found %d valid events.\n', length(relevantTTLs));
    end

    SessionData = struct();
    SessionData.Meta.SessionName = sessionName;
    SessionData.Meta.Window = [-winPre, winPost];
    SessionData.Meta.TrialMode = isTrial;
    SessionData.Meta.Units = 'uV'; 
    
    Regions = GetRegionMap(); 
    cscFiles = dir(fullfile(dataFolder, '*.ncs')); 
    fprintf('   > Found %d .ncs files.\n', length(cscFiles));
    
    uniqueIDs = unique(relevantTTLs);
    hasData = false; 
    currentFs = 0;

    for i = 1:length(uniqueIDs)
        evID = uniqueIDs(i);
        evName = EventDict(evID);
        evTimestamps = relevantTS(relevantTTLs == evID);
        
        if isTrial
            limit = 5;
            if length(evTimestamps) > limit
                evTimestamps = evTimestamps(1:limit);
                fprintf('\n   >>> EVENT: "%s" (ID: %d) | [TRIAL MODE: 5/%d]\n', evName, evID, length(relevantTS(relevantTTLs == evID)));
            else
                 fprintf('\n   >>> EVENT: "%s" (ID: %d) | Count: %d\n', evName, evID, length(evTimestamps));
            end
        else
            fprintf('\n   >>> EVENT: "%s" (ID: %d) | Count: %d\n', evName, evID, length(evTimestamps));
        end
        
        % --- LOOP THROUGH BRAIN REGIONS ---
        for r = 1:length(Regions)
            regName = Regions(r).Name;
            baseField = strrep(regName, ' ', '_'); 
            channels = Regions(r).Channels;
            
            % --- LOOP THROUGH CHANNELS INDIVIDUALLY ---
            for ch = channels
                if ch < 1 || ch > 32, continue; end
                
                fileIdx = FindFileForChannel(cscFiles, ch);
                if isempty(fileIdx), continue; end
                
                cscPath = fullfile(dataFolder, cscFiles(fileIdx).name);
                
                % EXTRACT
                [snippets, actualFs] = GetSnippets(cscPath, evTimestamps, winPre, winPost, useNativeFs, defaultFs, doInvert, doMicroVolts);
                
                if isempty(snippets), continue; end
                
                currentFs = actualFs; 
                
                % --- SAVE INDIVIDUALLY ---
                % Key Format: "Left_POR_Ch01"
                uniqueField = sprintf('%s_Ch%02d', baseField, ch);
                SessionData.(evName).(uniqueField) = snippets;
                
                hasData = true;
                fprintf('.'); % Progress dot for each channel
            end
        end
        fprintf(' Done.\n');
    end
    
    if hasData
        if ~isfield(SessionData.Meta, 'Fs')
            SessionData.Meta.Fs = currentFs;
        end
        
        outName = fullfile(outputDir, [sessionName '_ForPython.mat']);
        fprintf('\n[SAVE] Writing MAT file (v7.3)...\n');
        save(outName, 'SessionData', '-v7.3'); 
        fprintf('   > Saved: %s\n', outName);
    else
        fprintf(2, '\n[FAILURE] No data extracted.\n');
    end
end

% =========================================================================
% HELPERS
% =========================================================================
function Events = ManualEventLoad(nevFile)
    Events = struct('TimeStamps', [], 'TTLs', []);
    if ~exist(nevFile, 'file'), return; end

    fid = fopen(nevFile, 'r', 'ieee-le');
    if fid == -1, return; end
    
    try
        fseek(fid, 16384, 'bof'); 
        fseek(fid, 0, 'eof');
        numRecords = floor((ftell(fid) - 16384) / 184);
        
        fseek(fid, 16384, 'bof');
        ts = zeros(1, numRecords);
        ttls = zeros(1, numRecords);
        
        for i = 1:numRecords
            fread(fid, 3, 'int16');        
            ts(i) = fread(fid, 1, 'uint64'); 
            fread(fid, 1, 'int16');        
            ttls(i) = fread(fid, 1, 'int16');
            fread(fid, 166, 'uint8');      
        end
        
        Events.TimeStamps = ts;
        Events.TTLs = ttls;
    catch
    end
    fclose(fid);
end

function [snippets, actualFs] = GetSnippets(filePath, eventTimes, pre, post, useNativeFs, defaultFs, doInvert, doMicroVolts)
    snippets = []; 
    actualFs = defaultFs;
    
    try
        H = Nlx2MatCSC(filePath, [0 0 0 0 0], 1, 1, []);
        line = H(contains(H, 'SamplingFrequency'));
        nativeFs = str2double(regexp(line{1}, '\d+(\.\d+)?', 'match'));
        if isempty(nativeFs), nativeFs = 32000; end
        
        lineAD = H(contains(H, 'ADBitVolts', 'IgnoreCase', true));
        if ~isempty(lineAD)
            tok = regexp(lineAD{1}, '[\-+]?\d+(\.\d+)?([eE][\-+]?\d+)?', 'match'); 
            ADBitVolts = str2double(tok{1});
        else
            ADBitVolts = 6e-8; 
        end
    catch
        return; 
    end
    
    if useNativeFs, targetFs = nativeFs; else, targetFs = defaultFs; end
    actualFs = targetFs;
    
    try
        [TS, Samples] = Nlx2MatCSC(filePath, [1 0 0 0 1], 0, 1, []);
    catch
        return;
    end
    
    if isempty(TS), return; end
    
    flatSamples = Samples(:);
    
    % UNITS
    flatSamples = double(flatSamples) * ADBitVolts;
    if doMicroVolts, flatSamples = flatSamples * 1e6; end
    if doInvert, flatSamples = flatSamples * -1; end
    
    t0 = double(TS(1));
    totalDur = length(flatSamples) / nativeFs * 1e6;
    fullTime = linspace(t0, t0 + totalDur, length(flatSamples));
    
    numEvents = length(eventTimes);
    outPoints = round((pre + post) * targetFs); 
    snippets = zeros(numEvents, outPoints);
    
    for i = 1:numEvents
        centerT = double(eventTimes(i));
        startT  = centerT - (pre * 1e6);
        
        idxStart = find(fullTime >= startT, 1, 'first');
        if isempty(idxStart), continue; end
        
        if useNativeFs
             idxEnd = idxStart + outPoints - 1;
        else
             chunkLenRaw = round((pre+post) * nativeFs);
             idxEnd = idxStart + chunkLenRaw - 1;
        end
        
        if idxEnd > length(flatSamples), continue; end
        
        rawClip = flatSamples(idxStart:idxEnd);
        
        if useNativeFs
            if length(rawClip) == outPoints
                snippets(i, :) = rawClip;
            elseif length(rawClip) > outPoints
                snippets(i, :) = rawClip(1:outPoints);
            else
                snippets(i, 1:length(rawClip)) = rawClip;
            end
        else
            snippets(i, :) = imresize(rawClip, [outPoints, 1], 'bilinear');
        end
    end
end

function idx = FindFileForChannel(fileList, chNum)
    idx = [];
    for k = 1:length(fileList)
        fname = fileList(k).name;
        digits = regexp(fname, '\d+', 'match');
        if ~isempty(digits)
            fNum = str2double(digits{1});
            if fNum == chNum
                idx = k; return;
            end
        end
    end
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