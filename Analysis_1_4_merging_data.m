%% Paired-Ca merging — conforms to Results_A1 v1 (no Calcium_mM field).
%   Pairs runs of the same ROI at 1 mM and 2 mM external Ca2+ and stores
%   the concatenated (1mM -> 2mM) result in one slot of Results_A1
%   indexed by Imaged_area_index. Also emits Analysis_1_template_paired.xlsx
%   listing one row per emitted pair.

clearvars -except select_f Analysis_template Paired_template include_singletons;
close all;

% --- Options ---
if ~exist('include_singletons', 'var')
    include_singletons = false;   % true => pass through unpaired ROIs as one-run entries
end

% --- Load or create Results_A1 ---
mat_file = 'Analysis_1_Results.mat';

if exist(mat_file, 'file')
    load(mat_file);
    fprintf('Loaded existing Results structure from %s\n', mat_file);
    if isfield(Results_A1, 'Calcium_mM')
        Results_A1 = rmfield(Results_A1, 'Calcium_mM');
        fprintf('Stripped legacy Calcium_mM field to conform to Results_A1 v1.\n');
    end
else
    fprintf('File not found. Creating new Results structure...\n');

    Results_A1 = struct( ...
        'Folder',            {[]}, ...
        'Run_name',          {{}}, ...
        'Run_index',         {[]}, ...
        'Imaged_area_index', {[]}, ...
        'Paradigm',          {[]}, ...
        'Acquisition',       {[]}, ...
        'Frame_data',        struct, ...
        'AP_data',           struct, ...
        'Bouton_metadata',   struct, ...
        'Bouton',            struct, ...
        'Bouton_rings',      struct);

    Results_A1(200).Folder = '';
    save(mat_file, 'Results_A1');
    fprintf('New Results structure saved as %s\n', mat_file);
end

% --- Templates ---
if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template.xlsx';
end
if ~exist('Paired_template', 'var')
    Paired_template = 'Analysis_1_template_paired.xlsx';
end
input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');

if ~exist('select_f', 'var')
    select_f = 2;
end

% --- Trackers ---
error_log = struct('row', {}, 'folder', {}, 'run_name', {}, 'message', {}, 'stack', {});
skipped_singletons = {};

% --- Group rows by (Cell number, Imaged_area_index) preserving first-seen order ---
row_idx = select_f(:) - 1;
groups = containers.Map('KeyType', 'char', 'ValueType', 'any');
ordered_keys = {};
for f = row_idx'
    cell_num = input_list{f, 1};
    roi      = input_list{f, 5};
    key      = sprintf('%d_%d', cell_num, roi);
    if isKey(groups, key)
        g = groups(key); g(end+1) = f; groups(key) = g;
    else
        groups(key) = f;
        ordered_keys{end+1} = key; %#ok<SAGROW>
    end
end

% --- Process each group ---
for gi = 1:length(ordered_keys)
    key  = ordered_keys{gi};
    rows = groups(key);

    clear idx is_new_entry cell_num;

    try
        cell_num = input_list{rows(1), 1};
        Folder   = string(input_list{rows(1), 2});
        roi      = input_list{rows(1), 5};

        % Parse Ca for each row
        ca_vals = nan(1, length(rows));
        run_names_in = strings(1, length(rows));
        for ii = 1:length(rows)
            rn = char(input_list{rows(ii), 3});
            run_names_in(ii) = string(rn);
            tok = regexp(rn, '(\d+)mM', 'tokens', 'once');
            if ~isempty(tok), ca_vals(ii) = str2double(tok{1}); end
        end

        % Decide group fate (singleton / paired / malformed)
        if length(rows) == 1
            if ~include_singletons
                msg = sprintf('Cell %d ROI %d (%s)', cell_num, roi, run_names_in(1));
                skipped_singletons{end+1} = msg; %#ok<SAGROW>
                fprintf('Skipping singleton: %s\n', msg);
                continue;
            end
            ordered_rows = rows;
        elseif length(rows) == 2
            if ~isequal(sort(ca_vals), [1 2])
                error('Ca tokens for ROI %d (cell %d) are not {1,2}: got [%s]', ...
                    roi, cell_num, num2str(ca_vals));
            end
            [~, order] = sort(ca_vals);   % 1mM first, 2mM second
            ordered_rows = rows(order);
        else
            % >=3 rows: take the first 2 by input_list order, provided their
            % Ca tokens differ. This salvages data instead of skipping the
            % whole group.
            first2_rows = rows(1:2);
            first2_ca   = ca_vals(1:2);
            if ~isequal(sort(first2_ca), [1 2])
                error(['Group (cell %d, ROI %d) has %d rows; first two are at ' ...
                    'Ca=[%s]mM (need one 1mM and one 2mM to pair).'], ...
                    cell_num, roi, length(rows), num2str(first2_ca));
            end
            [~, order] = sort(first2_ca);
            ordered_rows = first2_rows(order);
            dropped = rows(3:end);
            dropped_names = strjoin(cellstr(run_names_in(3:end)), ', ');
            fprintf(['  NOTE: (cell %d, ROI %d) has %d runs; using first two ' ...
                '(rows %d, %d) as the 1mM/2mM pair, dropping: %s\n'], ...
                cell_num, roi, length(rows), first2_rows(1)+1, first2_rows(2)+1, ...
                dropped_names);
        end

        % --- Run Calculation Unit Module on each run independently ---
        per_run = struct('FRAME_DATA', {}, 'AP_data_matrix', {}, ...
                         'N_samples', {}, 'T_end', {}, ...
                         'ROI_data', {}, 'metadata', {}, ...
                         'rings', {}, 'run_index', {}, 'run_name', {}, ...
                         'acquisition', {});
        for ii = 1:length(ordered_rows)
            f = ordered_rows(ii);
            run_name = char(input_list{f, 3});
            acquisition_mode = input_list{f, 7};
            stage3_folder = ['Stage_3_A1/', char(Folder), '/', run_name, '/'];

            metadata = readtable(fullfile(stage3_folder, 'bouton_metadata.csv'));
            metadata = metadata{:, :};

            ROI_tbl = readtable(fullfile(stage3_folder, 'mean_traces.csv'));
            ROI_data = ROI_tbl{:, :};

            raw_data = fullfile(['Stage_3_A1/', char(Folder), '/'], [run_name, '.mat']);

            if acquisition_mode
                run Calculation_Unit_Module_Analysis_1_4_new;
            else
                run Calculation_Unit_Module_Analysis_1_4_old;
            end

            per_run(ii).FRAME_DATA     = FRAME_DATA;
            per_run(ii).AP_data_matrix = AP_data_matrix;
            per_run(ii).N_samples      = length(T);
            per_run(ii).T_end          = T(end);
            per_run(ii).ROI_data       = ROI_data;
            per_run(ii).metadata       = metadata;
            per_run(ii).run_index      = input_list{f, 4};
            per_run(ii).run_name       = run_name;
            per_run(ii).acquisition    = acquisition_mode;

            rings_file = fullfile(stage3_folder, 'mean_traces_plus_rings.mat');
            if exist(rings_file, 'file')
                rd = load(rings_file);
                per_run(ii).rings = rd.ring_incl_centre;
            else
                per_run(ii).rings = struct();
            end

            fprintf('  loaded run %s (Ca=%dmM, frames=%d, APs=%d)\n', ...
                run_name, ca_vals(ordered_rows == f), ...
                size(FRAME_DATA{1,1}, 1), size(AP_data_matrix, 1));
        end

        n_runs = length(per_run);

        % --- Bouton count consistency for pairs ---
        if n_runs == 2 && size(per_run(1).metadata, 1) ~= size(per_run(2).metadata, 1)
            error('Bouton count mismatch for (cell %d, ROI %d): %d vs %d', ...
                cell_num, roi, size(per_run(1).metadata, 1), size(per_run(2).metadata, 1));
        end

        % --- Build merged outputs ---
        if n_runs == 1
            FRAME_OUT = per_run(1).FRAME_DATA;

            apm = per_run(1).AP_data_matrix;
            if length(per_run(1).ROI_data) ~= length(per_run(1).FRAME_DATA{1})
                apm = [apm, apm(:, 2) - 1];
            else
                apm = [apm, apm(:, 2)];
            end
            AP_OUT = {apm};

            BOUTON_OUT   = [(1:size(per_run(1).ROI_data, 1))', per_run(1).ROI_data];
            METADATA_OUT = per_run(1).metadata;
            RINGS_OUT    = per_run(1).rings;
        else
            FD1 = per_run(1).FRAME_DATA{1, 1};
            FD2 = per_run(2).FRAME_DATA{1, 1};

            N_frames_1  = size(FD1, 1);
            N_samples_1 = per_run(1).N_samples;
            T_end_1     = per_run(1).T_end;
            N_AP_1      = size(per_run(1).AP_data_matrix, 1);

            % Offset run-2 Frame_data{1,1}
            ncols = size(FD2, 2);
            FD2_shift = FD2;
            switch ncols
                case 11   % Acquisition = 1 (new module)
                    FD2_shift(:, 1)   = FD2_shift(:, 1)   + N_frames_1;
                    FD2_shift(:, 2:3) = FD2_shift(:, 2:3) + N_samples_1;
                    FD2_shift(:, 5:6) = FD2_shift(:, 5:6) + T_end_1;
                    % cols 4, 7, 8, 9, 10, 11 are within-frame quantities — unchanged
                case 15   % Acquisition = 0 (old module)
                    FD2_shift(:, 1)     = FD2_shift(:, 1)     + N_frames_1;
                    FD2_shift(:, 2:3)   = FD2_shift(:, 2:3)   + N_samples_1;
                    FD2_shift(:, 5:6)   = FD2_shift(:, 5:6)   + T_end_1;
                    FD2_shift(:, 8:10)  = FD2_shift(:, 8:10)  + N_samples_1;
                    FD2_shift(:, 12:14) = FD2_shift(:, 12:14) + T_end_1;
                    % cols 4, 7, 11, 15 are durations — unchanged
                otherwise
                    error('Unexpected FRAME_DATA{1,1} column count: %d', ncols);
            end
            FD_combined = [FD1; FD2_shift];

            % Average the trailing summary cells
            nC = length(per_run(1).FRAME_DATA);
            FRAME_OUT = cell(1, nC);
            FRAME_OUT{1, 1} = FD_combined;
            for j = 2:nC
                FRAME_OUT{1, j} = (per_run(1).FRAME_DATA{1, j} + ...
                                   per_run(2).FRAME_DATA{1, j}) / 2;
            end

            % Offset run-2 AP_data, then append col 6 per-run, then concat
            ap1 = per_run(1).AP_data_matrix;
            ap2 = per_run(2).AP_data_matrix;
            if ~isempty(ap2)
                ap2(:, 1) = ap2(:, 1) + N_AP_1;
                ap2(:, 2) = ap2(:, 2) + N_frames_1;
                ap2(:, 3) = ap2(:, 3) + N_samples_1;
                ap2(:, 4) = ap2(:, 4) + T_end_1;
            end

            if length(per_run(1).ROI_data) ~= length(per_run(1).FRAME_DATA{1})
                ap1 = [ap1, ap1(:, 2) - 1];
            else
                ap1 = [ap1, ap1(:, 2)];
            end
            if ~isempty(ap2)
                if length(per_run(2).ROI_data) ~= length(per_run(2).FRAME_DATA{1})
                    ap2 = [ap2, ap2(:, 2) - 1];
                else
                    ap2 = [ap2, ap2(:, 2)];
                end
            end
            AP_OUT = {[ap1; ap2]};

            % Bouton: stack rows, continue frame index in 2mM block
            n1 = size(per_run(1).ROI_data, 1);
            n2 = size(per_run(2).ROI_data, 1);
            B1 = [(1:n1)',            per_run(1).ROI_data];
            B2 = [((n1+1):(n1+n2))',  per_run(2).ROI_data];
            BOUTON_OUT = [B1; B2];

            METADATA_OUT = per_run(1).metadata;

            % Rings: concat along time dim if both numeric
            r1 = per_run(1).rings; r2 = per_run(2).rings;
            if isnumeric(r1) && isnumeric(r2) && ~isempty(r1) && ~isempty(r2)
                RINGS_OUT = cat(1, r1, r2);
            else
                RINGS_OUT = struct();
            end
        end

        % --- Output identity ---
        if n_runs == 1
            new_run_name = sprintf('%d_%dmM', roi, ca_vals(1));
            new_run_index = per_run(1).run_index;
        else
            new_run_name  = sprintf('%d_1mM_2mM', roi);
            new_run_index = str2double([num2str(per_run(1).run_index), ...
                                        num2str(per_run(2).run_index)]);
        end

        % Find existing slot for this (cell, ROI), or append a new one
        match_index = find(Results_A1(cell_num).Imaged_area_index == roi);
        if ~isempty(match_index)
            idx = match_index(1);
            is_new_entry = false;
        else
            idx = length(Results_A1(cell_num).Imaged_area_index) + 1;
            is_new_entry = true;
        end

        % Ensure Run_name is a cell array on this element
        if ~iscell(Results_A1(cell_num).Run_name)
            Results_A1(cell_num).Run_name = {};
        end

        Results_A1(cell_num).Folder                 = Folder;
        Results_A1(cell_num).Run_name{idx}          = string(new_run_name);
        Results_A1(cell_num).Run_index(idx)         = new_run_index;
        Results_A1(cell_num).Imaged_area_index(idx) = roi;
        Results_A1(cell_num).Paradigm(idx)          = input_list{ordered_rows(1), 6};
        Results_A1(cell_num).Acquisition(idx)       = input_list{ordered_rows(1), 7};

        Results_A1(cell_num).Frame_data(idx).data      = FRAME_OUT;
        Results_A1(cell_num).AP_data(idx).data         = AP_OUT;
        Results_A1(cell_num).Bouton(idx).data          = BOUTON_OUT;
        Results_A1(cell_num).Bouton_metadata(idx).data = METADATA_OUT;
        Results_A1(cell_num).Bouton_rings(idx).data    = RINGS_OUT;

        % --- Save progress ---
        save('Analysis_1_Results', 'Results_A1');

        fprintf('Processed (cell %d, ROI %d) -> %s [run_index %d]\n', ...
            cell_num, roi, new_run_name, new_run_index);

    catch ME
        % Roll back a freshly appended pair entry so only successful pairs remain
        if exist('is_new_entry', 'var') && is_new_entry && exist('idx', 'var') ...
                && exist('cell_num', 'var') ...
                && idx == length(Results_A1(cell_num).Run_index)
            Results_A1(cell_num).Run_name(idx) = [];
            Results_A1(cell_num).Run_index(idx) = [];
            Results_A1(cell_num).Imaged_area_index(idx) = [];
            Results_A1(cell_num).Paradigm(idx) = [];
            Results_A1(cell_num).Acquisition(idx) = [];
            if idx <= length(Results_A1(cell_num).Bouton)
                Results_A1(cell_num).Bouton(idx) = [];
            end
            if idx <= length(Results_A1(cell_num).Bouton_metadata)
                Results_A1(cell_num).Bouton_metadata(idx) = [];
            end
            if idx <= length(Results_A1(cell_num).Frame_data)
                Results_A1(cell_num).Frame_data(idx) = [];
            end
            if idx <= length(Results_A1(cell_num).AP_data)
                Results_A1(cell_num).AP_data(idx) = [];
            end
            if idx <= length(Results_A1(cell_num).Bouton_rings)
                Results_A1(cell_num).Bouton_rings(idx) = [];
            end
        end

        cur_folder = ''; cur_run = '';
        try
            cur_folder = char(input_list{rows(1), 2});
            cur_run    = char(input_list{rows(1), 3});
        catch
        end
        error_log(end+1) = struct( ...
            'row',      rows(1) + 1, ...
            'folder',   cur_folder, ...
            'run_name', cur_run, ...
            'message',  ME.message, ...
            'stack',    ME.stack); %#ok<SAGROW>
        fprintf('  *** ERROR on group %s (first row %d): %s\n', key, rows(1) + 1, ME.message);
        save('Analysis_1_Results', 'Results_A1');
    end
end

% --- Final rebuild of paired template from full Results_A1 ---
n_emitted = rebuild_paired_template(Results_A1, input_list, Paired_template);
fprintf('Wrote %s with %d paired rows (from full Results_A1).\n', Paired_template, n_emitted);

%% --- Skipped singletons report ---
if ~isempty(skipped_singletons)
    fprintf('\n=== Skipped singletons (include_singletons=false) ===\n');
    for k = 1:length(skipped_singletons)
        fprintf('  %s\n', skipped_singletons{k});
    end
end

%% --- Error report ---
if isempty(error_log)
    fprintf('\nAll done. No errors encountered.\n');
else
    fprintf('\n=== ERROR REPORT ===\n');
    fprintf('Total failures: %d\n', length(error_log));
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
    save('A1_4_error_log.mat', 'error_log');
    fprintf('Error log saved to A1_4_error_log.mat\n');
end

disp('All analysis done.');

%% ====================================================================
function n_emitted = rebuild_paired_template(Results_A1, input_list, Paired_template)
% Rebuild the paired template spreadsheet by scanning every populated
% (cell, ROI) slot of Results_A1. Cols 1-7 are sourced from Results_A1;
% cols 8+ (inert metadata) are copied from the matching input-template
% row (preferring the 1mM row of the pair). Slots whose (cell, ROI) pair
% does not appear in input_list at all are skipped with a warning.

vnames = input_list.Properties.VariableNames;

% --- Lookup: (cell_num, roi) -> input_list row, preferring 1mM ---
lookup = containers.Map('KeyType', 'char', 'ValueType', 'any');
for i = 1:height(input_list)
    c  = input_list{i, 1};
    rr = input_list{i, 5};
    rn = char(input_list{i, 3});
    key = sprintf('%d_%d', c, rr);
    is_1mM = ~isempty(regexp(rn, '(^|[^0-9])1mM', 'once'));
    if ~isKey(lookup, key) || is_1mM
        lookup(key) = i;
    end
end

out = input_list([], :);

for c = 1:numel(Results_A1)
    if isempty(Results_A1(c).Folder) || isempty(Results_A1(c).Run_index)
        continue;
    end
    for r = 1:length(Results_A1(c).Run_index)
        if Results_A1(c).Run_index(r) == 0, continue; end
        if r > length(Results_A1(c).Imaged_area_index), continue; end
        if Results_A1(c).Imaged_area_index(r) == 0, continue; end

        roi = Results_A1(c).Imaged_area_index(r);
        key = sprintf('%d_%d', c, roi);
        if ~isKey(lookup, key)
            warning('Paired entry (cell %d, ROI %d) is not in input_list; skipping in paired template.', c, roi);
            continue;
        end

        row = input_list(lookup(key), :);

        row.(vnames{1}) = c;
        row = assign_col(row, vnames{2}, char(Results_A1(c).Folder));
        row = assign_col(row, vnames{3}, char(Results_A1(c).Run_name{r}));
        row.(vnames{4}) = Results_A1(c).Run_index(r);
        row.(vnames{5}) = Results_A1(c).Imaged_area_index(r);
        row.(vnames{6}) = Results_A1(c).Paradigm(r);
        row.(vnames{7}) = Results_A1(c).Acquisition(r);

        out = [out; row]; %#ok<AGROW>
    end
end

if exist(Paired_template, 'file'), delete(Paired_template); end
if ~isempty(out)
    writetable(out, Paired_template);
end
n_emitted = height(out);
end

function row = assign_col(row, vname, value)
% Assign a string-ish value into a table cell, preserving column type.
orig = row.(vname);
if iscell(orig)
    row.(vname) = {value};
elseif isstring(orig)
    row.(vname) = string(value);
else
    row.(vname) = {value};
end
end
