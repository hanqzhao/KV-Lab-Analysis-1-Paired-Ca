%% Combined max projection across runs of the same ROI
%
% For each (Cell number, ROI index) group in select_f, build an
% amplitude-preserving combined max projection by inverting the Stage 1_1
% forward transform per run, taking the pixel-wise max on the common ΔF
% scale, and applying a single scale16 to produce the uint16 output.
%
% Stage 0_3 must have been run first so that all members share the same
% coordinate frame and image size.
%
% Input :  Stage_3_A1/<folder>/<run_name>/max_proj_unscaled.mat
%            .max_proj_unscaled  - double [H × W]
%            .norm_scale         - stretch factor
% Output:  Stage_3_A1/<folder>/<run_name>/Max_img_combined.tif

clearvars -except select_f Analysis_template;
close all;

import A1_funs.*

disp('Combined max projection started')

if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template_new.xlsx';
end
if ~exist('select_f', 'var')
    select_f = 2;
end

input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');

% Build groups: unique (Cell number, ROI index) pairs within select_f
rows           = select_f(:) - 1;
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
    n_members = length(member_rows);

    fprintf('\n--- Group %d/%d: Cell %d, ROI %d (%d run%s) ---\n', ...
            g, n_groups, cell_num, roi_idx, n_members, ...
            repmat('s', 1, n_members ~= 1));

    try
        % Load each member's pre-scale16 max projection + forward transform
        unscaled  = cell(n_members, 1);
        folders   = cell(n_members, 1);
        run_names = cell(n_members, 1);

        for m = 1:n_members
            r            = member_rows(m);
            folders{m}   = char(input_list.(2)(r));
            run_names{m} = char(input_list.(3)(r));
            FNAME = fullfile('Stage_3_A1', folders{m}, run_names{m}, ...
                             'max_proj_unscaled.mat');
            if ~isfile(FNAME)
                error('Unscaled max projection not found: %s', FNAME);
            end
            data = load(FNAME, 'max_proj_unscaled', 'norm_scale');
            % Invert the Stage 1_1 forward transform:
            %   subtract 2000  - undo the offset added in pipeline units
            %   / norm_scale   - undo the two scale16fast stretches
            % Result is proportional to ΔF in raw camera counts and is
            % directly comparable between runs.
            unscaled{m} = (double(data.max_proj_unscaled) - 2000) ...
                          / data.norm_scale;
            fprintf('  Loaded member %d: norm_scale = %.4g\n', m, data.norm_scale);
        end

        % All members must share the same image size (guaranteed by 0_3)
        sizes = cell2mat(cellfun(@(x) [size(x, 1), size(x, 2)], unscaled, ...
                                 'UniformOutput', false));
        if size(unique(sizes, 'rows'), 1) ~= 1
            error(['Unscaled max projections in group have inconsistent ', ...
                   'sizes. Make sure Stage 0_3 was re-run for all members.']);
        end

        % Pixel-wise maximum on the common ΔF scale
        combined_unscaled = unscaled{1};
        for m = 2:n_members
            combined_unscaled = max(combined_unscaled, unscaled{m});
        end

        % Single uint16 scaling for Stage 1_2.
        % scale16 returns double here (input is double); cast to uint16 so
        % imwrite produces a uint16 TIFF — otherwise imwrite would treat the
        % double matrix as range [0,1] and clip everything to white.
        combined = uint16(scale16(combined_unscaled));

        % Write to every member's folder
        for m = 1:n_members
            out_path = fullfile('Stage_3_A1', folders{m}, run_names{m}, ...
                                'Max_img_combined.tif');
            imwrite(combined, out_path);
        end

        fprintf('  Wrote Max_img_combined.tif to %d member folder(s).\n', ...
                n_members);

    catch ME
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
    end
    save('A1_1b_combined_max_error_log.mat', 'error_log');
    fprintf('Error log saved to A1_1b_combined_max_error_log.mat\n');
end
