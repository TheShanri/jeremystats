% convert_mat_to_csv.m
% Loads 'all_group_phase.mat' and exports each group to a separate CSV file.

clc; clear; close all;

% 1. Configuration
filename = 'all_group_phase.mat';
outputDir = 'csv_exports';

% 2. Create output directory if it doesn't exist
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

% 3. Load the MAT file
fprintf('Loading %s...\n', filename);
try
    data = load(filename);
catch ME
    error('Could not load file. Make sure "%s" is in the current folder.', filename);
end

% 4. Check for 'groupedData'
if ~isfield(data, 'groupedData')
    error('Variable "groupedData" not found in the MAT file.');
end

groupedData = data.groupedData;

% 5. Identify if it is a Struct or a Map
if isstruct(groupedData)
    groups = fieldnames(groupedData);
    fprintf('Found %d groups in struct.\n', length(groups));
    
    for i = 1:length(groups)
        groupName = groups{i};
        groupTable = groupedData.(groupName);
        
        % Define output filename
        outName = fullfile(outputDir, [groupName, '.csv']);
        
        % Write to CSV
        try
            writetable(groupTable, outName);
            fprintf('Saved: %s\n', outName);
        catch ME
            fprintf('Error saving %s: %s\n', groupName, ME.message);
        end
    end
    
else
    error('groupedData is not a struct. It is class: %s. Please adjust script.', class(groupedData));
end

fprintf('Done! Check the "%s" folder.\n', outputDir);