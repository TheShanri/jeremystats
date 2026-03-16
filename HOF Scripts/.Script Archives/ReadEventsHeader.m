function Header = ReadEventsHeader(baseFolder)
% READEVENTSHEADER Extracts the header from a Neuralynx events.nev file.
%
%   Header = ReadEventsHeader(baseFolder)
%
%   INPUT:
%       baseFolder - String path to the session folder.
%
%   OUTPUT:
%       Header     - Mx1 Cell Array of strings containing file metadata.

    %% 1. Construct Path
    nevFullPath = fullfile(baseFolder, 'DATA', 'events.nev');

    if ~isfile(nevFullPath)
        % Try case-insensitive check
        nevFullPathAlt = fullfile(baseFolder, 'DATA', 'Events.nev');
        if isfile(nevFullPathAlt)
            nevFullPath = nevFullPathAlt;
        else
            error('File not found: %s', nevFullPath);
        end
    end

    %% 2. Setup "Dummy" Extraction to Fix MEX Bug
    % The Nlx2MatEV function often fails if you ask for the Header ONLY.
    % WORKAROUND: We ask for Timestamps (Field 1) AND Header.
    % We also limit it to reading just the 1st record so it is instant.
    
    % FieldSelection: [Time, ID, TTL, Extras, String]
    FieldSelection = [1 0 0 0 0]; % Request Timestamps only
    
    ExtractHeader = 1; % Yes, get the header
    ExtractMode = 2;   % Extract by Record Index
    ModeArray = [1 1]; % Read only index 1 to 1 (just one line)
    
    fprintf('Reading Header from: %s\n', nevFullPath);
    
    try
        % We must provide TWO output variables: [Timestamps, Header]
        % even though we will throw away the timestamp.
        [~, Header] = Nlx2MatEV(nevFullPath, FieldSelection, ExtractHeader, ExtractMode, ModeArray);
        
        % Check if Header is empty (another common MEX failure mode)
        if isempty(Header)
            error('Nlx2MatEV returned an empty header. File might be corrupt.');
        end

        % Display the results
        fprintf('\n--- HEADER CONTENT ---\n');
        for i = 1:length(Header)
            if contains(Header{i}, '-TimeCreated') || ...
               contains(Header{i}, '-TimeClosed') || ...
               contains(Header{i}, '-OriginalFileName')
                fprintf('%s\n', Header{i});
            end
        end
        fprintf('----------------------\n');
        
    catch ME
        error(['Failed to read Header.\n' ...
               'Error: %s\n' ...
               'Note: Ensure Nlx2MatEV.mexw64 matches your MATLAB version (64-bit).'], ME.message);
    end

end