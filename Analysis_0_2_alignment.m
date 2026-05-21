%% Alignment

clearvars -except select_f Analysis_template;
close all;

% imports
import A1_funs.*

disp('Alignment started')

if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template.xlsx';
end
par_folder = '_paradigms';

% Select which lines to do from the Excel Analysis template
if ~exist('select_f', 'var')
    select_f = 2;
end

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

        % Input from Stage_1_organised
        input_folder = ['Stage_1_organised/', folder, '/', run_name, '/'];
        FNAME = fullfile(input_folder, [run_name, '.tif']);

        % Output to Stage_2_aligned
        out_folder = ['Stage_2_aligned/', folder, '/', run_name, '/'];
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

        %% Aligning image stack

        tAlign = tic;
        fprintf('aligning...\n')

        % Read the correct paradigm
        if par_number == 0
            paradigm = 0;
        elseif par_number == 1
            paradigm = paradigms{1};
        else
            index = find(par_numbers == par_number);
            paradigm = paradigms{index};
        end

        % Get subsweep lengths from table
        subsweep_lengths = paradigm{:, 1};
        num_subsweeps = length(subsweep_lengths);

        % Calculate frame indices for each subsweep
        subsweep_ends = cumsum(subsweep_lengths);
        subsweep_starts = [1; subsweep_ends(1:end-1) + 1];

        % Compute mean image for each subsweep
        fprintf('  computing subsweep means (%d subsweeps)...', num_subsweeps)
        subsweep_means = zeros(dim1, dim2, num_subsweeps);
        for s = 1:num_subsweeps
            subsweep_means(:,:,s) = mean(imageStack_temp(:,:,subsweep_starts(s):subsweep_ends(s)), 3);
        end
        fprintf('done\n')

        % Reference: first subsweep mean (filtered for robustness)
        ref_filtered = imgaussfilt(subsweep_means(:,:,1), 2);

        % Set up intensity-based registration
        [optimizer, metric] = imregconfig('monomodal');
        optimizer.MaximumIterations = 300;
        optimizer.MaximumStepLength = 0.0625;
        optimizer.MinimumStepLength = 1e-6;
        optimizer.RelaxationFactor = 0.5;

        % Calculate transforms for each subsweep
        fprintf('  calculating subsweep transforms...')
        transforms = cell(num_subsweeps, 1);
        transforms{1} = affine2d(eye(3));  % Identity for first subsweep

        for s = 2:num_subsweeps
            moving_filtered = imgaussfilt(subsweep_means(:,:,s), 2);
            transforms{s} = imregtform(moving_filtered, ref_filtered, 'translation', optimizer, metric);
        end
        fprintf('done\n')

        % Display detected shifts
        fprintf('  Detected shifts (pixels):\n')
        fprintf('    Subsweep | X-shift | Y-shift\n')
        for s = 1:num_subsweeps
            T = transforms{s}.T;
            fprintf('    %7d  | %+7.2f | %+7.2f\n', s, T(3,1), T(3,2))
        end

        % Apply transforms to all frames within each subsweep
        fprintf('  applying transforms to frames...')
        output_view = imref2d([dim1, dim2]);

        for s = 2:num_subsweeps
            tform = transforms{s};

            % Skip if no significant shift
            if abs(tform.T(3,1)) < 0.01 && abs(tform.T(3,2)) < 0.01
                continue;
            end

            % Apply same transform to all frames in this subsweep
            for k = subsweep_starts(s):subsweep_ends(s)
                imageStack_temp(:,:,k) = imwarp(imageStack_temp(:,:,k), tform, 'OutputView', output_view);
            end
        end
        fprintf('done\n')

        % Mask selecting pixels > 0 for whole time domain
        global_mask = all(imageStack_temp > 0, 3);

        % Bounding box of mask
        stats = regionprops(global_mask, 'BoundingBox');
        bbox = stats.BoundingBox;

        % Convert bounding box to integer pixel indices
        x_min = floor(bbox(1)) + 1;
        y_min = floor(bbox(2)) + 1;
        x_max = x_min + floor(bbox(3)) - 1;
        y_max = y_min + floor(bbox(4)) - 1;

        % Crop image stack
        imageStack_temp = imageStack_temp(y_min:y_max, x_min:x_max, :);

        % Save aligned stack to Stage_2_aligned
        OUTPUT_A = fullfile(out_folder, 'aligned.tif');
        TIFF_write(OUTPUT_A, imageStack_temp);

        % Save unaligned subsweep averages
        unaligned_avg = fullfile(out_folder, 'unaligned_averages.tif');
        TIFF_write(unaligned_avg, uint16(subsweep_means));
        
        % Compute aligned subsweep averages
        aligned_means = zeros(size(imageStack_temp,1), size(imageStack_temp,2), num_subsweeps, 'uint16');
        for s = 1:num_subsweeps
            aligned_means(:,:,s) = uint16(mean(imageStack_temp(:,:,subsweep_starts(s):subsweep_ends(s)), 3));
        end
        
        % Save aligned subsweep averages
        aligned_avg = fullfile(out_folder, 'aligned_averages.tif');
        TIFF_write(aligned_avg, aligned_means);
        
        % Save transforms as CSV
        transform_table = table((1:num_subsweeps)', zeros(num_subsweeps,1), zeros(num_subsweeps,1), ...
            'VariableNames', {'Subsweep', 'X_shift', 'Y_shift'});
        for s = 1:num_subsweeps
            transform_table.X_shift(s) = transforms{s}.T(3,1);
            transform_table.Y_shift(s) = transforms{s}.T(3,2);
        end
        writetable(transform_table, fullfile(out_folder, 'transforms.csv'));

        fprintf('alignment complete. ')
        tAlign = toc(tAlign);
        fprintf('%.2f seconds\n', tAlign);

        % Copy .mat file from Stage_1_organised to Stage_2_aligned
        mat_source = fullfile(['Stage_1_organised/', folder, '/'], [run_name, '.mat']);
        mat_dest_folder = ['Stage_2_aligned/', folder, '/'];
        if ~exist(mat_dest_folder, 'dir')
            mkdir(mat_dest_folder);
        end
        if isfile(mat_source)
            copyfile(mat_source, fullfile(mat_dest_folder, [run_name, '.mat']));
            fprintf('Copied .mat: %s\n', mat_source);
        else
            fprintf('WARNING: .mat not found: %s\n', mat_source);
        end

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
    save('A0_2_alignment_error_log.mat', 'error_log');
    fprintf('Error log saved to alignment_error_log.mat\n');
end
