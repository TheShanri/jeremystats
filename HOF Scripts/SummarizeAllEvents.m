function SummarizeAllEvents(rootDir)
% SUMMARIZEALLEVENTS - Fixed: robust path naming and dimension handling.

    % 1. SETUP
    if nargin < 1
        error('Please provide the root directory path.');
    end
    
    % Check for loader (using exist=3 for mex, 2 for m)
    if exist('Nlx2MatEV', 'file') == 0
        error('Neuralynx loader (Nlx2MatEV) not found! Add it to your path.');
    end

    disp(['Searching for Events.nev files in: ' rootDir ' ...']);
    files = dir(fullfile(rootDir, '**', 'Events.nev'));
    
    if isempty(files)
        error('No Events.nev files found.');
    end
    
    disp(['Found ' num2str(length(files)) ' files. Processing...']);
    
    MasterTable = table();

    % 2. LOOP THROUGH FILES
    for i = 1:length(files)
        filePath = fullfile(files(i).folder, files(i).name);
        
        try
            % --- A. SMARTER PATH PARSING ---
            % Get the folder parts
            pathParts = split(files(i).folder, filesep);
            
            % Gracefully handle different depths. 
            % We look for the last 3 folders relative to the file.
            % If the path is too short, we pad with "Unknown".
            len = length(pathParts);
            
            if len >= 3
                RatID = pathParts{end-2};      % e.g. J1
                SessionID = pathParts{end-1};  % e.g. Con1
                RecordingID = pathParts{end};  % e.g. 2025-09-16...
            elseif len == 2
                RatID = pathParts{end-1};
                SessionID = pathParts{end};
                RecordingID = 'RootRec';
            else
                RatID = 'Unknown';
                SessionID = 'Unknown';
                RecordingID = pathParts{end};
            end
            
            fprintf('Processing: %s | %s ... ', RatID, SessionID);

            % --- B. LOAD NEURALYNX EVENTS ---
            % FieldSelection: [timestamps, EventIDs, TTLs, Extras, EventStrings]
            [TimeStamps, EventIDs, TTLs, EventStrings] = Nlx2MatEV(filePath, [1 1 1 0 1], 0, 1);
            
            if isempty(TimeStamps)
                fprintf('Skipping (Empty File).\n');
                continue;
            end
            
            % --- C. FORCE VERTICAL COLUMNS (The Fix) ---
            % The (:) syntax forces any array into a single vertical column.
            % This prevents the "Row vs Column" table error.
            
            % 1. Normalize Time
            StartTime = TimeStamps(1);
            t_sec = double(TimeStamps(:) - StartTime) / 1000000;
            
            % 2. Force Data Vectors
            ttl_val = double(TTLs(:));
            evt_id = double(EventIDs(:));
            
            % 3. Handle Strings (Convert Cell Array to String Array)
            evt_str = string(EventStrings(:));
            
            % 4. Create Metadata Columns (Same length as data)
            numEvents = length(t_sec);
            r_col = repmat(string(RatID), numEvents, 1);
            s_col = repmat(string(SessionID), numEvents, 1);
            d_col = repmat(string(RecordingID), numEvents, 1);

            % --- D. BUILD TABLE ---
            T = table(r_col, s_col, d_col, t_sec, ttl_val, evt_id, evt_str, ...
                'VariableNames', {'RatID', 'Session', 'RecordingDir', 'Time_s', 'TTL', 'EventID', 'EventString'});
            
            % Append
            MasterTable = [MasterTable; T]; %#ok<AGROW>
            fprintf('Success (%d events).\n', numEvents);
            
        catch ME
            fprintf('\n   !!! CRITICAL ERROR on file: %s\n', files(i).name);
            fprintf('   Error Message: %s\n', ME.message);
        end
    end

    % 3. SAVE
    if ~isempty(MasterTable)
        outputFile = fullfile(rootDir, 'All_Events_Summary.xlsx');
        writetable(MasterTable, outputFile);
        disp('------------------------------------------------');
        disp(['DONE. Saved to: ' outputFile]);
    else
        disp('No valid data found to save.');
    end
end