% This script reads a Neuralynx .ncs file from a specific file path and saves it as a .mat file.

% --- SCRIPT START ---

% 1. Define the full path to the input and output files.
%    - Replace 'C:\MyData\2024\Exp1\my_data.ncs' with the actual path to your file.
%    - The output .mat file will be saved in the same directory.
ncsFilePath = 'C:\MyData\2024\Exp1\my_data.ncs'; 
[folder, name, ~] = fileparts(ncsFilePath);
matFilePath = fullfile(folder, [name '.mat']);

% 2. Check if the input file exists.
if ~exist(ncsFilePath, 'file')
    error('File not found: %s', ncsFilePath);
end

% 3. Call the Nlx2MatCSC() function.
fprintf('Reading data from %s...\n', ncsFilePath);
[Timestamps, ScNumbers, SampleFrequencies, NumberOfValidSamples, Samples, Header] = ...
    Nlx2MatCSC(ncsFilePath, [1 1 1 1 1], 1, 1, []);

% 4. Save the retrieved data to the specified .mat file path.
fprintf('Saving data to %s...\n', matFilePath);
save(matFilePath, 'Timestamps', 'ScNumbers', 'SampleFrequencies', ...
    'NumberOfValidSamples', 'Samples', 'Header');

% 5. Display a success message.
fprintf('Conversion complete! Data saved successfully.\n');

% --- SCRIPT END ---