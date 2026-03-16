function events = SummarizeEvents(basePath)
% SUMMARIZEEVENTS_MANUAL_OVERRIDE
% Bypasses Nlx2MatEV entirely to manually parse corrupt Neuralynx files.

    % --- 1. SETUP PATHS ---
    dataFolder = fullfile(basePath, 'DATA');
    nevFile = fullfile(dataFolder, 'Events.nev');
    
    if ~exist(nevFile, 'file')
        error('File not found: %s', nevFile);
    end
    
    fprintf('MANUAL READ: %s\n', nevFile);

    % --- 2. OPEN FILE ---
    fid = fopen(nevFile, 'r', 'ieee-le'); % Little Endian is standard for Neuralynx
    if fid == -1
        error('Could not open file.');
    end

    try
        % --- 3. SKIP HEADER ---
        % The header is exactly 16384 bytes. We jump over it.
        headerSize = 16384; 
        fseek(fid, 0, 'eof');
        fileSize = ftell(fid);
        
        if fileSize < headerSize
             error('File is smaller than the header (Empty).');
        end
        
        numBytesData = fileSize - headerSize;
        recordSize = 184; % Standard NEV record size
        numRecords = numBytesData / recordSize;
        
        fprintf('   > File Size: %d bytes\n', fileSize);
        fprintf('   > Data Block: %d bytes\n', numBytesData);
        fprintf('   > Calculated Records: %.2f\n', numRecords);

        if mod(numBytesData, recordSize) ~= 0
            warning('Data size is not a multiple of 184. Attempting to read anyway...');
            numRecords = floor(numRecords);
        end
        
        if numRecords == 0
             fprintf('   > No records found after header.\n');
             events = []; 
             fclose(fid);
             return;
        end

        % --- 4. MANUAL EXTRACTION ---
        % We go back to the start of the data
        fseek(fid, headerSize, 'bof');
        
        % Pre-allocate arrays
        TimeStamps = zeros(1, numRecords);
        TTLs = zeros(1, numRecords);
        EventStrings = cell(1, numRecords);
        
        fprintf('   > Manually parsing %d records...\n', numRecords);
        
        for i = 1:numRecords
            % NEV Record Structure (184 bytes total):
            % [0-1]   int16: nstx (reserved)
            % [2-3]   int16: npkt_id 
            % [4-5]   int16: npkt_data_size
            % [6-13]  uint64: TimeStamp  <-- WE WANT THIS
            % [14-15] int16: EventID
            % [16-17] int16: TTL         <-- WE WANT THIS
            % [18-19] int16: CRC
            % [20-21] int16: Dummy
            % [22-53] int32: Extras (8 values)
            % [54-181] char: EventString (128 bytes) <-- OFTEN CORRUPT
            
            % Read Packet Header (6 bytes)
            fread(fid, 3, 'int16'); 
            
            % Read Timestamp (8 bytes)
            ts = fread(fid, 1, 'uint64');
            TimeStamps(i) = ts;
            
            % Read EventID (2 bytes)
            fread(fid, 1, 'int16');
            
            % Read TTL (2 bytes)
            ttl = fread(fid, 1, 'int16');
            TTLs(i) = ttl;
            
            % Skip the rest of the record (CRC, Dummy, Extras, String)
            % Remaining bytes = 184 - (6 + 8 + 2 + 2) = 166 bytes
            fread(fid, 166, 'uint8'); 
            
            % Mark string as manual extraction
            EventStrings{i} = sprintf('Manual_Extract_TTL_%d', ttl);
        end
        
        % --- 5. BUILD OUTPUT ---
        events.TimeStamps = TimeStamps;
        events.EventIDs = ones(1, numRecords); % Dummy
        events.TTLs = TTLs;
        events.Extras = [];
        events.EventStrings = EventStrings;
        events.Header = {'Manual Override Header'};
        
        fprintf('   > SUCCESS. Extracted %d events.\n', numRecords);
        fprintf('   > Timestamps: %s\n', mat2str(TimeStamps));
        fprintf('   > TTLs: %s\n', mat2str(TTLs));

    catch ME
        fclose(fid);
        rethrow(ME);
    end
    
    fclose(fid);
end