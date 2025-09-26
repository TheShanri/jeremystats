% This script will read a Neuralynx .ncs file and save the data to a .mat file.

% --- SCRIPT START ---

% 1. Define the input and output filenames.
%    - Replace 'your_data.ncs' with the actual name of your Neuralynx file.
%    - The output file will have the same name but with a .mat extension.
ncsFileName = 'your_data.ncs'; 
matFileName = 'your_data.mat';

% 2. Check if the input file exists.
%    - This is good practice to prevent errors.
if ~exist(ncsFileName, 'file')
    error('File not found: %s', ncsFileName);
end

% 3. Call the Nlx2MatCSC() function to read the data.
%    - This is the core function that does the work.
%    - The arguments specify what data to retrieve from the .ncs file.
%    - [1 1 1 1 1] tells the function to get all outputs: Timestamps, ScNumbers,
%      SampleFrequencies, NumberOfValidSamples, and Samples.
%    - The '1's after that are flags for including the header and how to handle
%      invalid samples.
fprintf('Reading data from %s...\n', ncsFileName);
[Timestamps, ScNumbers, SampleFrequencies, NumberOfValidSamples, Samples, Header] = ...
    Nlx2MatCSC(ncsFileName, [1 1 1 1 1], 1, 1, []);

% 4. Save the retrieved data to a .mat file.
%    - The 'save' function creates a binary file that stores the variables.
%    - This makes it easy to load the data later without re-running the
%      Neuralynx conversion.
fprintf('Saving data to %s...\n', matFileName);
save(matFileName, 'Timestamps', 'ScNumbers', 'SampleFrequencies', ...
    'NumberOfValidSamples', 'Samples', 'Header');

% 5. Display a success message.
fprintf('Conversion complete! Data saved successfully.\n');

% --- SCRIPT END ---