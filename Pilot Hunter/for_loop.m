% --- BATCH SCRIPT START ---

% 1. Define the base input folder.
%    - If your files are in the current working directory, use 'pwd'.
%    - If they are in a specific folder, replace 'pwd' with the folder path
%      (e.g., 'C:\MyData\2024\Exp1\').
inputFolder = "D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26";

% 2. Loop through files CS1.ncs to CS64.ncs
for i = 1:3
    % Construct the current file name (e.g., 'CS1.ncs', 'CS2.ncs', etc.)
    currentFileName = sprintf('CSC%d.ncs', i);
    
    % Define the full path to the input and output files.
    ncsFilePath = fullfile(inputFolder, currentFileName);
    
    % Use fileparts to get the name without extension for the output .mat file
    [folder, name, ~] = fileparts(ncsFilePath);
    matFilePath = fullfile(folder, [name '.mat']);

    % 3. Check if the input file exists.
    if ~exist(ncsFilePath, 'file')
        fprintf('⚠️ Skipping: File not found: %s\n', ncsFilePath);
        continue; % Skip to the next iteration of the loop
    end

    % 4. Call the Nlx2MatCSC() function.
    fprintf('\n--- Processing file %d of 64: %s ---\n', i, currentFileName);
    fprintf('Reading data from %s...\n', ncsFilePath);
    
    try
        [Timestamps, ScNumbers, SampleFrequencies, NumberOfValidSamples, Samples, Header] = ...
            Nlx2MatCSC(ncsFilePath, [1 1 1 1 1], 1, 1, []);
        
        % 5. Save the retrieved data to the specified .mat file path.
        fprintf('Saving data to %s...\n', matFilePath);
        save(matFilePath, 'Timestamps', 'ScNumbers', 'SampleFrequencies', ...
            'NumberOfValidSamples', 'Samples', 'Header');
        
        % 6. Display a success message.
        fprintf('✅ Conversion complete for %s! Data saved successfully.\n', currentFileName);
        
    catch ME
        % Error handling for Nlx2MatCSC or save function
        fprintf('❌ An error occurred while processing %s: %s\n', currentFileName, ME.message);
        continue; % Move to the next file
    end
end

fprintf('\n--- BATCH PROCESSING COMPLETE ---\n');

% --- BATCH SCRIPT END ---

--- BATCH PROCESSING COMPLETE ---
for_loop

--- Processing file 1 of 64: CSC1.ncs ---
Reading data from D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26\CSC1.ncs...
	There was an error attempting to retrieve a string from index 0. Numeric data was found at that location.
❌ An error occurred while processing CSC1.ncs: One or more output arguments not assigned during call to "Nlx2MatCSC".

--- Processing file 2 of 64: CSC2.ncs ---
Reading data from D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26\CSC2.ncs...
	There was an error attempting to retrieve a string from index 0. Numeric data was found at that location.
❌ An error occurred while processing CSC2.ncs: One or more output arguments not assigned during call to "Nlx2MatCSC".

--- Processing file 3 of 64: CSC3.ncs ---
Reading data from D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26\CSC3.ncs...
	There was an error attempting to retrieve a string from index 0. Numeric data was found at that location.
❌ An error occurred while processing CSC3.ncs: One or more output arguments not assigned during call to "Nlx2MatCSC".

--- BATCH PROCESSING COMPLETE ---

