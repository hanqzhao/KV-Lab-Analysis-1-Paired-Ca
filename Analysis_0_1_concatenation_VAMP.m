%% Stitching different sections of the sweep together

clearvars -except select_f Analysis_template;
close all;
clc;

import A1_funs.*

% The template spreadsheet
if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template_new.xlsx';
end
input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');

% Select which lines to do from the Excel Analysis template
if ~exist('select_f', 'var')
    select_f = 2;
end

% Define the name of the image stack
ifname = '_MMStack_Default.ome.tif';

% the wcp file names, in time order
wfname = '*.wcp';

% Input and output root directories
inputRoot  = 'raw';
outputRoot = 'Stage_1_organised';

% Number of parts expected
expectedParts = 5;

% Track which rows passed and failed
passedRows = [];
failedRows = {};  % stores {row number, error message}

tracker = 1;
for f = select_f - 1
    fprintf('============================================================\n');
    fprintf('Analysing image %d of %d\n', tracker, length(select_f));

    % Grab row info before try block so we can report it on failure
    folder   = char(input_list.(2)(f));
    run_name = char(input_list.(3)(f));
    rowNum   = f + 1;

    fprintf('[ROW %d] Folder: %s | Run: %s\n', rowNum, folder, run_name);
    fprintf('============================================================\n');

    try
        % -------------------------------------------------------
        % For each part 1 to 5, find the latest version
        % -------------------------------------------------------
        base_folder = fullfile(inputRoot, folder);

        selected_sections = cell(expectedParts, 1);

        for p = 1:expectedParts

            pattern    = fullfile(base_folder, sprintf('%s_%d*', run_name, p));
            candidates = dir(pattern);
            candidates = candidates([candidates.isdir]);

            validCandidates = {};
            versionNumbers  = [];

            for c = 1:length(candidates)
                name   = candidates(c).name;
                prefix = sprintf('%s_%d', run_name, p);

                if strcmp(name, prefix)
                    validCandidates{end+1} = name;
                    versionNumbers(end+1)  = 1;
                else
                    remainder = strrep(name, [prefix, '_'], '');
                    if ~isempty(regexp(remainder, '^\d+$', 'once'))
                        validCandidates{end+1} = name;
                        versionNumbers(end+1)  = str2double(remainder);
                    end
                end
            end

            if isempty(validCandidates)
                error('No folder found for part %d of run: %s', p, run_name);
            end

            [~, bestIdx]         = max(versionNumbers);
            selected_sections{p} = validCandidates{bestIdx};

            fprintf('  Part %d: using folder "%s"\n', p, selected_sections{p});
        end

        % -------------------------------------------------------
        % Loop over the 5 selected sections and stitch
        % -------------------------------------------------------
        stitchedStack = [];
        Y = [];
        T = [];
        time_passed = 0;

        for i = 1:expectedParts
            sub_run_name = selected_sections{i};
            sub_folder   = fullfile(base_folder, sub_run_name);

            FNAME = fullfile(sub_folder, [sub_run_name, ifname]);

            fprintf('\n  Loading part %d: %s\n', i, FNAME);

            % Load the image stack
            info   = imfinfo(FNAME);
            dim1   = info(1).Height;
            dim2   = info(1).Width;
            dim3   = length(info);
            imageStack_temp = zeros(dim1, dim2, dim3, 'uint16');
            parfor k = 1:dim3
                currentImage = imread(FNAME, k, 'Info', info);
                imageStack_temp(:, :, k) = currentImage;
            end

            stitchedStack = cat(3, stitchedStack, imageStack_temp);

            % Load ephys files
            wcp_files = dir(fullfile(sub_folder, wfname));
            if isempty(wcp_files)
                error('No .wcp file found in: %s', sub_folder);
            end
            wcp_fp = fullfile(wcp_files(1).folder, wcp_files(1).name);

            out = import_wcp(wcp_fp, 'debug');

            % Read out the channel values
            Y_temp = zeros(length(out.S{1,1}), 4);
            Y_temp(:,1) = out.S{1,1}; % Channel AI0: primary - current
            Y_temp(:,2) = out.S{1,2}; % Channel AI1: secondary - command voltage
            Y_temp(:,3) = out.S{1,5}; % Channel AI5: Cam Exposure
            Y_temp(:,4) = out.S{1,3}; % Channel AI3: User 1 - camera trigger

            % Read out the time values
            T_temp = out.T.';
            T_temp = T_temp + time_passed;

            % Add to arrays
            Y = [Y; Y_temp];
            T = [T; T_temp];

            time_passed = time_passed + max(T_temp);
        end

        % -------------------------------------------------------
        % Save outputs to Stage_1_organised/
        % -------------------------------------------------------
        output_folder = fullfile(outputRoot, folder, run_name);
        OUTPUT        = fullfile(output_folder, [run_name, '.tif']);
        save_location = fullfile(outputRoot, folder);

        if ~exist(output_folder, 'dir')
            mkdir(output_folder);
            fprintf('\n  Created output folder: %s\n', output_folder);
        end

        if ~exist(save_location, 'dir')
            mkdir(save_location);
        end

        if exist(OUTPUT, 'file') == 2
            delete(OUTPUT);
            fprintf('  Deleted existing .tif: %s\n', OUTPUT);
        end

        fprintf('\n  Writing stitched stack to: %s\n', OUTPUT);
        A1_funs.TIFF_write(OUTPUT, stitchedStack);

        matOutput = fullfile(save_location, run_name);
        fprintf('  Saving ephys data to: %s.mat\n', matOutput);
        save(matOutput, 'T', 'Y');

        fprintf('\n  >>> [ROW %d] PASSED: %s\n\n', rowNum, run_name);
        passedRows(end+1) = rowNum;

    catch ME
        % Log the error and continue to the next row
        fprintf('\n  >>> [ROW %d] FAILED: %s\n', rowNum, run_name);
        fprintf('      Error: %s\n\n', ME.message);
        failedRows{end+1} = struct('row', rowNum, ...
                                   'folder', folder, ...
                                   'run_name', run_name, ...
                                   'error', ME.message);
    end

    tracker = tracker + 1;
end

% -------------------------------------------------------
% Final Summary
% -------------------------------------------------------
fprintf('============================================================\n');
fprintf(' SUMMARY\n');
fprintf('============================================================\n');
fprintf(' Total rows:   %d\n', length(passedRows) + length(failedRows));
fprintf(' Passed:       %d\n', length(passedRows));
fprintf(' Failed:       %d\n', length(failedRows));

if ~isempty(passedRows)
    fprintf('\n --- Passed rows ---\n');
    fprintf('  Row %d\n', passedRows);
end

if ~isempty(failedRows)
    fprintf('\n --- Failed rows ---\n');
    for i = 1:length(failedRows)
        fprintf('  [ROW %d] Folder: %s | Run: %s\n', ...
                failedRows{i}.row, ...
                failedRows{i}.folder, ...
                failedRows{i}.run_name);
        fprintf('           Error: %s\n', failedRows{i}.error);
    end
end

fprintf('============================================================\n');
