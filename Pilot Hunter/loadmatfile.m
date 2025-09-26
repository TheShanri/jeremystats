% This script loads a .mat file, plots the neural data, and saves the plot as a PNG image.

% --- SCRIPT START ---

% 1. Use 'uigetfile' to open a file selection dialog.
%    - The filter '*.mat' ensures the user can only select .mat files.
%    - This is more flexible than hardcoding a filename.
[matFileName, matFolderPath] = uigetfile('*.mat', 'Select a .mat file to plot');

% 2. Check if the user selected a file.
%    - 'uigetfile' returns 0 if the user clicks 'Cancel'.
if isequal(matFileName, 0)
    disp('File selection cancelled by user.');
    return; % Exit the script
end

% 3. Construct the full file paths for both the input data and the output plot.
matFilePath = fullfile(matFolderPath, matFileName);
[~, name, ~] = fileparts(matFileName); % Get the filename without the extension
plotFileName = [name '_plot.png'];
plotFilePath = fullfile(matFolderPath, plotFileName);

% 4. Load the data from the .mat file into the MATLAB workspace.
%    - This brings all the variables you saved earlier (Timestamps, Samples, etc.)
%      back into memory.
fprintf('Loading data from %s...\n', matFilePath);
load(matFilePath);

% 5. Select the data to plot.
%    - The 'Samples' variable is a matrix. We will plot the first channel (the first row).
%    - The 'Timestamps' are in microseconds, so we will convert them to seconds for a
%      more readable x-axis.
firstChannelData = Samples(1,:);
timeInSeconds = Timestamps / 1e6; % Convert microseconds to seconds

% 6. Create a new figure and plot the data.
%    - The 'figure' command creates a new plotting window.
%    - The 'plot' function draws the graph, with time on the x-axis and voltage on the y-axis.
%    - We set the line color to blue for clarity.
fprintf('Creating and customizing the plot...\n');
figure;
plot(timeInSeconds, firstChannelData, 'b');

% 7. Add labels and a title to the plot.
%    - It's important to label your axes so the plot is easy to understand.
title(['Continuous Neural Data from ' name]);
xlabel('Time (seconds)');
ylabel('Voltage (microvolts)');
grid on; % Add a grid to the plot for easier reading

% 8. Save the figure as an image file.
%    - The 'saveas' function exports the current figure to a file.
%    - The 'png' format is good for web and documents. You could also use 'jpg' or 'fig'.
fprintf('Saving plot as %s...\n', plotFilePath);
saveas(gcf, plotFilePath);

% 9. Display a success message.
fprintf('Plotting complete! The plot has been saved as %s.\n', plotFilePath);

% --- SCRIPT END ---
