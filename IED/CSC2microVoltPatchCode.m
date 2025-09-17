function CSC2microVoltPatchCode(filePath)
%CSC2microVoltPatchCode  Convert saved Neuralynx CSC data (AD units) to microvolts
%
% Usage:
%    CSC2microVoltPatchCode('C:\data\CSC1.mat')

    if nargin < 1
        [fname, fdir] = uigetfile('*.mat','Select CSC .mat file');
        if isequal(fname,0), return; end
        filePath = fullfile(fdir,fname);
    end

    % ---- parameters ----
    ADBitVolts = 0.00000006103515625;  % volts per AD
    scaleFactor = ADBitVolts * 1e6;    % microvolts per AD

    % ---- load the .mat ----
    S = load(filePath);
    vars = fieldnames(S);

    % assume the main signal is the largest numeric array
    sz = cellfun(@numel, struct2cell(S));
    [~, idx] = max(sz);
    sigName = vars{idx};
    rawSig = S.(sigName);

    % ---- scale ----
    microV = rawSig * scaleFactor;

    % ---- save back (append "_uV" to variable) ----
    S.(sigName) = microV;
    newName = [sigName '_uV'];
    S.(newName) = microV;

    [fdir,fname,ext] = fileparts(filePath);
    outFile = fullfile(fdir, [fname '_uV' ext]);
    save(outFile,'-struct','S','-v7.3');

    fprintf('Saved microvolt-scaled data to:\n%s\n', outFile);
end
