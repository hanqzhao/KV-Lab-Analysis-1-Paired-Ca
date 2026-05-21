%% Define image input file and the parameters of filters

clearvars -except select_f Analysis_template;
close all;

% imports
import A1_funs.*

disp('Analysis started - you can have a cup of tea')

if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template_new.xlsx';
end
par_folder = '_paradigms';

% Select which lines to do from the Excel Analysis template
if ~exist('select_f', 'var')
    select_f = 2;
end

% output file names
outputFileName1 = 'Img_filt.tif';
outputFileName2 = 'Max_img_filt.tif';
outputFileName3 = 'Cml_img_filt.tif';

% Define the order of the temporal binomial filter (default = 3)
bi_order = 3;

% Define the properties of the moving average filter
% This should be an odd number >= 3 (default = 3)
m = 3;

% Define the properties of the spatial Wiener filter
% odd number >= 3 (default = 5)
n = 5;

% Save img_filt (choose if you want to - it takes a lot of memory space)
save_process = 'No';

% Save cumulative max projection (choose if you want to again)
save_process_cml = 'No';

%% Loading image

input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');
headers = input_list.Properties.VariableNames;

% Read the paradigms
[paradigms, par_numbers] = readParadigms(par_folder);

tracker = 1;

% --- Error tracking ---
error_log = struct('row', {}, 'folder', {}, 'run_name', {}, 'message', {}, 'stack', {});

for f = select_f - 1
    fprintf('Analysing image %d of %d\n', tracker, length(select_f));

    try
        folder = char(input_list.(2)(f));
        run_name = char(input_list.(3)(f));
        par_number = input_list{f, 6};

        % Input from Stage_2b_cross_aligned (cross-run aligned stack)
        input_folder = ['Stage_2b_cross_aligned/', folder, '/', run_name, '/'];
        FNAME = fullfile(input_folder, 'aligned.tif');

        % Output to Stage_3_A1
        out_folder = ['Stage_3_A1/', folder, '/', run_name, '/'];
        if ~exist(out_folder, 'dir')
            mkdir(out_folder);
        end

        tLoad = tic;
        fprintf('loading the image...')

        % This part loads the image-stack
        info = imfinfo(FNAME);
        dim1 = info(1).Height;
        dim2 = info(1).Width;
        dim3 = length(info);
        imageStack_temp = zeros(dim1, dim2, dim3, 'uint16');
        parfor k = 1:dim3
            currentImage = imread(FNAME, k, 'Info', info);
            imageStack_temp(:, :, k) = currentImage;
        end

        fprintf('done. ')
        tLoad = toc(tLoad);
        fprintf('%f seconds\n', tLoad);

        % Read the correct paradigm
        if par_number == 0
            paradigm = 0;
        elseif par_number == 1
            paradigm = paradigms{1};
        else
            index = find(par_numbers == par_number);
            paradigm = paradigms{index};
        end

        %%  Spatial filtering

        % Record stretch #1 parameters (for Stage 1_1b inversion)
        raw_min   = double(min(imageStack_temp(:)));
        raw_scale = 65535 / (double(max(imageStack_temp(:))) - raw_min);
        imageStack_temp = scale16fast(imageStack_temp);

        tSpatial = tic;
        fprintf('spatial filtering...')

        f_tmp = zeros(dim1, dim2, 'double');
        parfor k = 1:dim3
            f_tmp = imageStack_temp(:, :, k);
            f_tmp = wiener2(f_tmp, [n n]);
            f_tmp = medfilt2(f_tmp, [m m]);
            imageStack_temp(:, :, k) = f_tmp;
        end
        clearvars f_tmp;
        fprintf('done. ')
        tSpatial = toc(tSpatial);
        fprintf('%f seconds\n', tSpatial);

        %% Filtering and Smoothing of time series

        % Record stretch #2 parameters (for Stage 1_1b inversion)
        filt_min   = double(min(imageStack_temp(:)));
        filt_scale = 0.95 * 65535 / (double(max(imageStack_temp(:))) - filt_min);
        imageStack_temp = 0.95 * scale16fast(imageStack_temp);

        tFilter = tic;
        fprintf('time series filtering...')

        parfor i = 1:dim1
            y_tmp = zeros(dim3, 1, 'double');
            for j = 1:dim2
                y_tmp(:) = imageStack_temp(i, j, :);

                % Perform subsweep analysis and baseline removal
                if par_number ~= 0
                    y_tmp = subsweepAnalysis(y_tmp, paradigm);
                end

                % binomial smoothing
                y_tmp = bifilter(y_tmp, bi_order);

                y_tmp = y_tmp + 2000;

                imageStack_temp(i, j, :) = y_tmp;
            end
        end
        clearvars y_tmp;
        fprintf('done. ')
        tFilter = toc(tFilter);
        fprintf('%f seconds\n', tFilter);

        %% Saving the filtered stack and the max projection

        tSave = tic;
        fprintf('saving outputs...')

        % Save pre-scale16 max projection + overall forward transform.
        % Stage 1_1b inverts norm_scale to put paired runs on a common ΔF scale
        % before combining (amplitude-preserving max projection).
        max_proj_unscaled = max(imageStack_temp, [], 3);   % uint16 [H × W], pipeline units (ΔF+2000)
        norm_scale        = raw_scale * filt_scale;        % combined linear stretch
        save(fullfile(out_folder, 'max_proj_unscaled.mat'), ...
             'max_proj_unscaled', 'norm_scale');

        imageStack_temp = scale16(imageStack_temp);

        % Save filtered image stack
        OUTPUT1 = fullfile(out_folder, outputFileName1);
        condition = strcmp(save_process, 'Yes');
        if condition == 1
            if exist(OUTPUT1, 'file') == 2
                delete(OUTPUT1);
            end
            TIFF_write(OUTPUT1, imageStack_temp);
        end
        fprintf('done. ')
        tSave = toc(tSave);
        fprintf('%f seconds\n', tSave);

        % Save maximal projection
        OUTPUT2 = fullfile(out_folder, outputFileName2);
        imageStack_temp16_max = max(imageStack_temp, [], 3);
        imageStack_temp16_max = scale16(imageStack_temp16_max);
        imwrite(imageStack_temp16_max, OUTPUT2);

        % Save cumulative image (if you want to)
        OUTPUT3 = fullfile(out_folder, outputFileName3);
        condition2 = strcmp(save_process_cml, 'Yes');
        if condition2 == 1
            if exist(OUTPUT3, 'file') == 2
                delete(OUTPUT3);
            end
            imageStack_cml = cummax(imageStack_temp, 3);
            TIFF_write(OUTPUT3, imageStack_cml);
        end

        % Copy .mat file from Stage_2b_cross_aligned to Stage_3_A1
        mat_source = fullfile(['Stage_2b_cross_aligned/', folder, '/'], [run_name, '.mat']);
        mat_dest_folder = ['Stage_3_A1/', folder, '/'];
        if ~exist(mat_dest_folder, 'dir')
            mkdir(mat_dest_folder);
        end
        if isfile(mat_source)
            copyfile(mat_source, fullfile(mat_dest_folder, [run_name, '.mat']));
            fprintf('Copied .mat: %s\n', mat_source);
        else
            fprintf('WARNING: .mat not found: %s\n', mat_source);
        end

        disp('run finished')
        disp('.....')

    catch ME
        % Store the error details
        error_log(end+1) = struct( ...
            'row',      f + 1, ...
            'folder',   char(input_list.(2)(f)), ...
            'run_name', char(input_list.(3)(f)), ...
            'message',  ME.message, ...
            'stack',    ME.stack);
        fprintf('  *** ERROR on row %d: %s\n', f + 1, ME.message);
    end

    tracker = tracker + 1;
end

%% --- Error Report ---
if isempty(error_log)
    fprintf('\nAll done. No errors encountered.\n');
else
    fprintf('\n=== ERROR REPORT ===\n');
    fprintf('Total failures: %d / %d\n', length(error_log), length(select_f));
    fprintf('--------------------\n');
    for k = 1:length(error_log)
        fprintf('Row %d | Folder: %s | Run: %s\n', ...
            error_log(k).row, error_log(k).folder, error_log(k).run_name);
        fprintf('    Error: %s\n', error_log(k).message);
        if ~isempty(error_log(k).stack)
            fprintf('    Location: %s (line %d)\n\n', ...
                error_log(k).stack(1).name, error_log(k).stack(1).line);
        else
            fprintf('\n');
        end
    end

    % Save the error log
    save('A1_1_error_log.mat', 'error_log');
    fprintf('Error log saved to A1_error_log.mat\n');
end

disp('All analysis done - go back to work');
