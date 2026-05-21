%% Cross-run alignment
%
% For each (Cell number, ROI index) group in select_f, register the runs
% of that ROI to one another in 2D. The lowest-Run-index member of the
% group is the anchor; every other member is registered to it using the
% same intensity-based translation algorithm as Analysis_0_2_alignment.m,
% but using the whole-stack mean of each run as the registration input
% (rather than per-subsweep means).
%
% All members of a group are cropped to the intersection of their valid
% regions so that downstream stages can use a single bouton mask across
% the pair.
%
% Groups containing only one row in select_f are treated as a pair-of-one
% (identity transform; data passed through with no cropping).
%
% Input :  Stage_2_aligned/<folder>/<run_name>/aligned.tif
%          Stage_2_aligned/<folder>/<run_name>.mat
% Output:  Stage_2b_cross_aligned/<folder>/<run_name>/aligned.tif
%          Stage_2b_cross_aligned/<folder>/<run_name>/aligned_averages.tif
%          Stage_2b_cross_aligned/<folder>/<run_name>/unaligned_averages.tif
%          Stage_2b_cross_aligned/<folder>/<run_name>/transforms.csv
%          Stage_2b_cross_aligned/<folder>/<run_name>.mat

clearvars -except select_f Analysis_template;
close all;

import A1_funs.*

disp('Cross-run alignment started')

if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template_new.xlsx';
end
if ~exist('select_f', 'var')
    select_f = 2;
end

input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');

% Minimum normalised correlation between the anchor mean and each warped
% member mean in the final crop window. Anything below this triggers a
% warning - typically caused by the experimenter labelling two genuinely
% different ROIs with the same ROI index.
MIN_NCC = 0.5;

% Build groups: unique (Cell number, ROI index) pairs within select_f
rows           = select_f(:) - 1;            % 0-based table row indices
cells_for_rows = input_list{rows, 1};
rois_for_rows  = input_list{rows, 5};
[group_keys, ~, group_idx] = unique([cells_for_rows, rois_for_rows], 'rows');
n_groups = size(group_keys, 1);

fprintf('\n%d group(s) to process.\n', n_groups);

% --- Error tracking ---
error_log = struct('row', {}, 'folder', {}, 'run_name', {}, ...
                   'message', {}, 'stack', {});

for g = 1:n_groups
    cell_num = group_keys(g, 1);
    roi_idx  = group_keys(g, 2);
    member_rows = rows(group_idx == g);

    % Sort members by Run index ascending (lowest = anchor)
    runs_in_group       = input_list{member_rows, 4};
    [~, sort_idx]       = sort(runs_in_group);
    member_rows         = member_rows(sort_idx);
    n_members           = length(member_rows);

    fprintf('\n--- Group %d/%d: Cell %d, ROI %d (%d run%s) ---\n', ...
            g, n_groups, cell_num, roi_idx, n_members, ...
            repmat('s', 1, n_members ~= 1));

    try
        % -----------------------------------------------------------
        % Load all aligned stacks for this group
        % -----------------------------------------------------------
        stacks    = cell(n_members, 1);
        folders   = cell(n_members, 1);
        run_names = cell(n_members, 1);

        for m = 1:n_members
            r              = member_rows(m);
            folders{m}     = char(input_list.(2)(r));
            run_names{m}   = char(input_list.(3)(r));
            FNAME = fullfile('Stage_2_aligned', folders{m}, run_names{m}, ...
                             'aligned.tif');
            if ~isfile(FNAME)
                error('Aligned stack not found: %s', FNAME);
            end
            fprintf('  Loading member %d (run %d): %s\n', ...
                    m, input_list{r, 4}, FNAME);
            info = imfinfo(FNAME);
            H = info(1).Height; W = info(1).Width; Tn = length(info);
            s = zeros(H, W, Tn, 'uint16');
            parfor k = 1:Tn
                s(:, :, k) = imread(FNAME, k, 'Info', info);
            end
            stacks{m} = s;
        end

        % -----------------------------------------------------------
        % Pad all members to a common (H_max, W_max) so they share a
        % coordinate frame for registration
        % -----------------------------------------------------------
        Hs = cellfun(@(x) size(x, 1), stacks);
        Ws = cellfun(@(x) size(x, 2), stacks);
        H_max = max(Hs);
        W_max = max(Ws);

        for m = 1:n_members
            [H, W, Tn] = size(stacks{m});
            if H ~= H_max || W ~= W_max
                padded = zeros(H_max, W_max, Tn, 'uint16');
                padded(1:H, 1:W, :) = stacks{m};
                stacks{m} = padded;
            end
        end

        % -----------------------------------------------------------
        % Whole-stack means
        % -----------------------------------------------------------
        means = cell(n_members, 1);
        for m = 1:n_members
            means{m} = mean(stacks{m}, 3);
        end

        % -----------------------------------------------------------
        % Registration (same parameters as Stage 0_2)
        % -----------------------------------------------------------
        [optimizer, metric] = imregconfig('monomodal');
        optimizer.MaximumIterations = 300;
        optimizer.MaximumStepLength = 0.0625;
        optimizer.MinimumStepLength = 1e-6;
        optimizer.RelaxationFactor  = 0.5;

        transforms      = cell(n_members, 1);
        transforms{1}   = affine2d(eye(3));            % anchor
        ref_filtered    = imgaussfilt(means{1}, 2);

        if n_members > 1
            fprintf('  Cross-registering %d run(s) to anchor (run %d)...\n', ...
                    n_members - 1, input_list{member_rows(1), 4});
            for m = 2:n_members
                moving_filtered = imgaussfilt(means{m}, 2);
                transforms{m} = imregtform(moving_filtered, ref_filtered, ...
                                           'translation', optimizer, metric);
            end

            fprintf('  Detected shifts (pixels):\n');
            fprintf('    Run | Folder/Run name              | X-shift | Y-shift\n');
            for m = 1:n_members
                Ttf = transforms{m}.T;
                fprintf('    %3d | %-28s | %+7.2f | %+7.2f\n', ...
                        input_list{member_rows(m), 4}, ...
                        sprintf('%s/%s', folders{m}, run_names{m}), ...
                        Ttf(3, 1), Ttf(3, 2));
            end
        else
            fprintf('  Singleton group: no cross-registration needed.\n');
        end

        % -----------------------------------------------------------
        % Apply transforms to all frames of each non-anchor member
        % -----------------------------------------------------------
        output_view = imref2d([H_max, W_max]);
        for m = 2:n_members
            tform = transforms{m};
            if abs(tform.T(3, 1)) < 0.01 && abs(tform.T(3, 2)) < 0.01
                continue;
            end
            Tn = size(stacks{m}, 3);
            for k = 1:Tn
                stacks{m}(:, :, k) = imwarp(stacks{m}(:, :, k), tform, ...
                                            'OutputView', output_view);
            end
        end

        % -----------------------------------------------------------
        % Intersection of valid regions across all members
        % -----------------------------------------------------------
        global_mask = true(H_max, W_max);
        for m = 1:n_members
            global_mask = global_mask & all(stacks{m} > 0, 3);
        end

        stats = regionprops(global_mask, 'BoundingBox');
        if isempty(stats)
            error(['Group (Cell %d, ROI %d) has no common valid region ', ...
                   'after cross-alignment.'], cell_num, roi_idx);
        end
        % Use the largest connected region if there happens to be more than one
        if numel(stats) > 1
            areas = [stats.Area]; %#ok<NASGU> % Area not in BoundingBox-only props
        end
        bbox = stats(1).BoundingBox;
        x_min = floor(bbox(1)) + 1;
        y_min = floor(bbox(2)) + 1;
        x_max = x_min + floor(bbox(3)) - 1;
        y_max = y_min + floor(bbox(4)) - 1;

        % -----------------------------------------------------------
        % Registration-quality check: NCC between anchor mean and each
        % non-anchor warped mean, computed inside the final crop window.
        % Low NCC usually means the runs are not actually the same ROI.
        % -----------------------------------------------------------
        anchor_crop_mean = mean(stacks{1}(y_min:y_max, x_min:x_max, :), 3);
        ncc_values = ones(n_members, 1);
        if n_members > 1
            fprintf('  Cross-registration quality (normalised correlation vs anchor):\n');
            fprintf('    Run | NCC\n');
            for m = 2:n_members
                member_crop_mean = mean(stacks{m}(y_min:y_max, x_min:x_max, :), 3);
                ncc_values(m) = corr2(anchor_crop_mean, member_crop_mean);
                flag = '';
                if ncc_values(m) < MIN_NCC
                    flag = '   <-- LOW; check whether this is really the same ROI';
                end
                fprintf('    %3d | %.3f%s\n', ...
                        input_list{member_rows(m), 4}, ncc_values(m), flag);
            end
            if any(ncc_values(2:end) < MIN_NCC)
                fprintf(['  [WARN] Group (Cell %d, ROI %d): one or more ', ...
                         'members align poorly to the anchor (NCC < %.2f). ', ...
                         'The runs may not actually share an ROI - confirm ', ...
                         'the ROI labelling.\n'], cell_num, roi_idx, MIN_NCC);
            end
        end

        % -----------------------------------------------------------
        % Build transforms.csv content (one row per member)
        % -----------------------------------------------------------
        T_table = table((1:n_members)', ...
                        zeros(n_members, 1), ...
                        zeros(n_members, 1), ...
                        zeros(n_members, 1), ...
                        zeros(n_members, 1), ...
                        'VariableNames', ...
                        {'Member', 'Run_index', 'X_shift', 'Y_shift', ...
                         'NCC_vs_anchor'});
        for m = 1:n_members
            T_table.Run_index(m)     = input_list{member_rows(m), 4};
            T_table.X_shift(m)       = transforms{m}.T(3, 1);
            T_table.Y_shift(m)       = transforms{m}.T(3, 2);
            T_table.NCC_vs_anchor(m) = ncc_values(m);
        end

        % -----------------------------------------------------------
        % Crop, save each member
        % -----------------------------------------------------------
        for m = 1:n_members
            cropped     = stacks{m}(y_min:y_max, x_min:x_max, :);
            out_folder  = fullfile('Stage_2b_cross_aligned', folders{m}, ...
                                   run_names{m});
            if ~exist(out_folder, 'dir'); mkdir(out_folder); end

            TIFF_write(fullfile(out_folder, 'aligned.tif'), cropped);

            writetable(T_table, fullfile(out_folder, 'transforms.csv'));

            % Copy ephys .mat through
            mat_source = fullfile('Stage_2_aligned', folders{m}, ...
                                  [run_names{m}, '.mat']);
            mat_dest_folder = fullfile('Stage_2b_cross_aligned', folders{m});
            if ~exist(mat_dest_folder, 'dir'); mkdir(mat_dest_folder); end
            if isfile(mat_source)
                copyfile(mat_source, ...
                         fullfile(mat_dest_folder, [run_names{m}, '.mat']));
            else
                fprintf('  WARNING: .mat not found: %s\n', mat_source);
            end
        end

        fprintf('  Group done. Cropped to [%d x %d] px.\n', ...
                y_max - y_min + 1, x_max - x_min + 1);

    catch ME
        % Log the same error against every member of the failing group
        for m = 1:length(member_rows)
            r = member_rows(m);
            try
                fld = char(input_list.(2)(r));
                rn  = char(input_list.(3)(r));
            catch
                fld = ''; rn = '';
            end
            error_log(end + 1) = struct( ...
                'row',      r + 1, ...
                'folder',   fld, ...
                'run_name', rn, ...
                'message',  ME.message, ...
                'stack',    ME.stack); %#ok<AGROW>
        end
        fprintf('  *** ERROR in group (Cell %d, ROI %d): %s\n', ...
                cell_num, roi_idx, ME.message);
    end
end

%% --- Error Report ---
if isempty(error_log)
    fprintf('\nAll done. No errors encountered.\n');
else
    fprintf('\n=== ERROR REPORT ===\n');
    fprintf('Total failed row(s): %d\n', length(error_log));
    fprintf('--------------------\n');
    for k = 1:length(error_log)
        fprintf('Row %d | Folder: %s | Run: %s\n', ...
                error_log(k).row, error_log(k).folder, ...
                error_log(k).run_name);
        fprintf('    Error: %s\n', error_log(k).message);
        if ~isempty(error_log(k).stack)
            fprintf('    Location: %s (line %d)\n\n', ...
                    error_log(k).stack(1).name, ...
                    error_log(k).stack(1).line);
        else
            fprintf('\n');
        end
    end
    save('A0_3_cross_alignment_error_log.mat', 'error_log');
    fprintf('Error log saved to A0_3_cross_alignment_error_log.mat\n');
end
