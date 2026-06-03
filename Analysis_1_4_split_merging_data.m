%% Paired-Ca merging (split variant) — conforms to Results_A1 v1.
%   Pairs runs of the same ROI at 1 mM and 2 mM external Ca2+, but stores
%   each run as its own slot of Results_A1 (no concatenation). Run_index is
%   the original spreadsheet run-index; all other fields are read straight
%   from the input template (same as the legacy per-run merging script).
%
%   Filtering rules vs the input template:
%     - Singleton ROIs (only one Ca condition present) are discarded.
%     - Groups with 3+ runs at the same (Cell, ROI): keep the first two rows
%       (in input-list order) iff their Ca tokens are {1 mM, 2 mM}.
%     - Otherwise (e.g. first two share a Ca, or Ca tokens unparseable): skip
%       the group with a logged warning.
%
%   Companion output: Analysis_1_template_split.xlsx — the input template
%   filtered to just the rows that survived the pairing filter, written ONCE
%   at the end (not per-iteration).

clearvars -except select_f Analysis_template Split_template;
close all;

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
if ~exist('Split_template', 'var')
    Split_template = 'Analysis_1_template_split.xlsx';
end
input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');

if ~exist('select_f', 'var')
    select_f = 2;
end

% --- Trackers ---
error_log = struct('row', {}, 'folder', {}, 'run_name', {}, 'message', {}, 'stack', {});
skipped_groups = {};

% --- Group rows by (Cell number, Imaged_area_index), preserving first-seen order ---
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

% --- Resolve which (row1,row2) pairs survive the pairing filter ---
pairs = {};   % each element: 1x2 vector of input_list row indices, ordered as in input list
for gi = 1:length(ordered_keys)
    key  = ordered_keys{gi};
    rows = groups(key);

    cell_num = input_list{rows(1), 1};
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

    if length(rows) == 1
        msg = sprintf('Cell %d ROI %d (%s): singleton', cell_num, roi, run_names_in(1));
        skipped_groups{end+1} = msg; %#ok<SAGROW>
        fprintf('Skipping %s\n', msg);
        continue;
    end

    first2_rows = rows(1:2);
    first2_ca   = ca_vals(1:2);

    if ~isequal(sort(first2_ca), [1 2])
        msg = sprintf(['Cell %d ROI %d: first two rows have Ca=[%s]mM ' ...
            '(need {1,2}) — group skipped'], cell_num, roi, num2str(first2_ca));
        skipped_groups{end+1} = msg; %#ok<SAGROW>
        fprintf('Skipping %s\n', msg);
        continue;
    end

    if length(rows) > 2
        dropped_names = strjoin(cellstr(run_names_in(3:end)), ', ');
        fprintf(['  NOTE: (cell %d, ROI %d) has %d runs; keeping first two ' ...
            '(rows %d, %d), dropping: %s\n'], ...
            cell_num, roi, length(rows), first2_rows(1)+1, first2_rows(2)+1, dropped_names);
    end

    pairs{end+1} = first2_rows; %#ok<SAGROW>
end

n_pairs = length(pairs);
n_kept_rows = 2 * n_pairs;
fprintf('Pairing filter: %d input rows -> %d kept rows in %d pairs (%d groups skipped)\n', ...
    length(row_idx), n_kept_rows, n_pairs, length(skipped_groups));

% --- Per-pair processing: compute both runs first, commit only if both succeed ---
% If either run errors, neither is written to Results_A1, so the whole pair
% is dropped (no half-written pairs in the output).
for pi = 1:n_pairs
    pair_rows = pairs{pi};
    fprintf('Analysing pair %d of %d (rows %d, %d)\n', ...
        pi, n_pairs, pair_rows(1)+1, pair_rows(2)+1);

    try
        % --- Compute everything for both runs into a buffer (no Results_A1 writes) ---
        per_run = struct('select_f_cells', {}, 'Folder', {}, ...
                         'check_run', {}, 'run_name', {}, 'acquisition_mode', {}, ...
                         'metadata', {}, 'ROI_data', {}, ...
                         'FRAME_DATA', {}, 'AP_DATA', {}, 'rings_data', {}, ...
                         'imaged_area_index', {}, 'paradigm', {});

        for ii = 1:length(pair_rows)
            f = pair_rows(ii);

            select_f_cells   = input_list{f, 1};
            Folder           = string(input_list{f, 2});
            check_run        = input_list{f, 4};
            acquisition_mode = input_list{f, 7};

            run_name      = char(input_list{f, 3});
            stage3_folder = ['Stage_3_A1/', char(Folder), '/', run_name, '/'];

            metadata = readtable(fullfile(stage3_folder, 'bouton_metadata.csv'));
            metadata = metadata{:, :};

            fprintf('  Folder = %s, run = %i\n', Folder, check_run);

            ROI_tbl  = readtable(fullfile(stage3_folder, 'mean_traces.csv'));
            ROI_data = ROI_tbl{:, :};

            raw_data = fullfile(['Stage_3_A1/', char(Folder), '/'], [run_name, '.mat']);
            if acquisition_mode
                run Calculation_Unit_Module_Analysis_1_4_new;
            else
                run Calculation_Unit_Module_Analysis_1_4_old;
            end

            if length(ROI_data) ~= length(FRAME_DATA{1})
                AP_data_matrix = [AP_data_matrix, AP_data_matrix(:, 2) - 1];
            else
                AP_data_matrix = [AP_data_matrix, AP_data_matrix(:, 2)];
            end
            AP_DATA{1, 1} = AP_data_matrix;

            rings_file = fullfile(stage3_folder, 'mean_traces_plus_rings.mat');
            if exist(rings_file, 'file')
                rd = load(rings_file);
                rings_data = rd.ring_incl_centre;
            else
                rings_data = struct();
            end

            per_run(ii).select_f_cells    = select_f_cells;
            per_run(ii).Folder            = Folder;
            per_run(ii).check_run         = check_run;
            per_run(ii).run_name          = run_name;
            per_run(ii).acquisition_mode  = acquisition_mode;
            per_run(ii).metadata          = metadata;
            per_run(ii).ROI_data          = ROI_data;
            per_run(ii).FRAME_DATA        = FRAME_DATA;
            per_run(ii).AP_DATA           = AP_DATA;
            per_run(ii).rings_data        = rings_data;
            per_run(ii).imaged_area_index = input_list{f, 5};
            per_run(ii).paradigm          = input_list{f, 6};
        end

        % --- Both runs succeeded — commit to Results_A1 (append or update by Run_index) ---
        for ii = 1:length(per_run)
            p   = per_run(ii);
            cnum = p.select_f_cells;

            match_index = find(Results_A1(cnum).Run_index == p.check_run);
            if ~isempty(match_index)
                idx = match_index(1);
            else
                idx = length(Results_A1(cnum).Run_index) + 1;
            end

            if ~iscell(Results_A1(cnum).Run_name)
                Results_A1(cnum).Run_name = {};
            end

            Results_A1(cnum).Folder                  = p.Folder;
            Results_A1(cnum).Run_name{idx}           = string(p.run_name);
            Results_A1(cnum).Run_index(idx)          = p.check_run;
            Results_A1(cnum).Imaged_area_index(idx)  = p.imaged_area_index;
            Results_A1(cnum).Paradigm(idx)           = p.paradigm;
            Results_A1(cnum).Acquisition(idx)        = p.acquisition_mode;

            Results_A1(cnum).Bouton(idx).data          = [(1:size(p.ROI_data, 1))' p.ROI_data];
            Results_A1(cnum).Bouton_metadata(idx).data = p.metadata;
            Results_A1(cnum).Frame_data(idx).data      = p.FRAME_DATA;
            Results_A1(cnum).AP_data(idx).data         = p.AP_DATA;
            Results_A1(cnum).Bouton_rings(idx).data    = p.rings_data;
        end

        save('Analysis_1_Results', 'Results_A1');

    catch ME
        % One of the runs failed — nothing was written to Results_A1 for this
        % pair (writes happen only after both runs compute cleanly), so the
        % whole pair is dropped.
        cur_folder = ''; cur_run = '';
        f_for_log = pair_rows(1);
        try
            cur_folder = char(input_list{f_for_log, 2});
            cur_run    = char(input_list{f_for_log, 3});
        catch
        end

        error_log(end+1) = struct( ...
            'row',      f_for_log + 1, ...
            'folder',   cur_folder, ...
            'run_name', cur_run, ...
            'message',  ME.message, ...
            'stack',    ME.stack); %#ok<SAGROW>
        fprintf('  *** ERROR on pair (rows %d, %d): %s\n', ...
            pair_rows(1)+1, pair_rows(2)+1, ME.message);

        save('Analysis_1_Results', 'Results_A1');
    end
end

% --- Rebuild the split spreadsheet ONCE at the end by scanning Results_A1 ---
n_emitted = rebuild_split_template(Results_A1, input_list, Split_template);
fprintf('Wrote %s with %d rows (rebuilt from Results_A1).\n', Split_template, n_emitted);

% --- Reports ---
if ~isempty(skipped_groups)
    fprintf('\n=== SKIPPED GROUPS (%d) ===\n', length(skipped_groups));
    for k = 1:length(skipped_groups)
        fprintf('  %s\n', skipped_groups{k});
    end
end

if isempty(error_log)
    fprintf('\nAll done. No row-level errors encountered.\n');
else
    fprintf('\n=== ERROR REPORT ===\n');
    fprintf('Total failures: %d / %d pairs\n', length(error_log), n_pairs);
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
function n_emitted = rebuild_split_template(Results_A1, input_list, Split_template)
% Rebuild the split template by scanning every populated slot of Results_A1.
% Each slot becomes one row IFF its (cell, Imaged_area_index) group contains
% exactly the pair {1 mM, 2 mM} (so only paired data appears in the output).
% Cols 1-7 come from Results_A1; cols 8+ are copied from the matching
% input-template row (matched by (cell, run_name)).

vnames = input_list.Properties.VariableNames;

% --- Lookup: (cell_num, run_name) -> input_list row ---
lookup = containers.Map('KeyType', 'char', 'ValueType', 'double');
for i = 1:height(input_list)
    c  = input_list{i, 1};
    rn = char(input_list{i, 3});
    lookup(sprintf('%d|%s', c, rn)) = i;
end

% --- Collect populated slots and group by (cell, ROI) ---
slots_by_pair = containers.Map('KeyType', 'char', 'ValueType', 'any');
for c = 1:numel(Results_A1)
    if isempty(Results_A1(c).Folder) || isempty(Results_A1(c).Run_index)
        continue;
    end
    for r = 1:length(Results_A1(c).Run_index)
        if Results_A1(c).Run_index(r) == 0, continue; end
        if r > length(Results_A1(c).Imaged_area_index), continue; end
        roi = Results_A1(c).Imaged_area_index(r);
        if roi == 0, continue; end

        rn = char(Results_A1(c).Run_name{r});
        tok = regexp(rn, '(\d+)mM', 'tokens', 'once');
        if isempty(tok), continue; end
        ca = str2double(tok{1});

        key = sprintf('%d_%d', c, roi);
        entry = struct('c', c, 'r', r, 'ca', ca, 'run_name', rn);
        if isKey(slots_by_pair, key)
            g = slots_by_pair(key); g(end+1) = entry; slots_by_pair(key) = g;
        else
            slots_by_pair(key) = entry;
        end
    end
end

out = input_list([], :);

pair_keys = slots_by_pair.keys;
for k = 1:length(pair_keys)
    entries = slots_by_pair(pair_keys{k});
    cas = arrayfun(@(e) e.ca, entries);
    if ~isequal(sort(cas(:)'), [1 2])
        continue;   % not a clean 1/2 mM pair — exclude
    end

    for jj = 1:length(entries)
        e = entries(jj);
        lkey = sprintf('%d|%s', e.c, e.run_name);
        if ~isKey(lookup, lkey)
            warning(['Slot (cell %d, run_index %d, run_name %s) is not in ' ...
                'input_list; skipping in split template.'], e.c, e.r, e.run_name);
            continue;
        end
        row = input_list(lookup(lkey), :);

        row.(vnames{1}) = e.c;
        row = assign_col(row, vnames{2}, char(Results_A1(e.c).Folder));
        row = assign_col(row, vnames{3}, char(Results_A1(e.c).Run_name{e.r}));
        row.(vnames{4}) = Results_A1(e.c).Run_index(e.r);
        row.(vnames{5}) = Results_A1(e.c).Imaged_area_index(e.r);
        row.(vnames{6}) = Results_A1(e.c).Paradigm(e.r);
        row.(vnames{7}) = Results_A1(e.c).Acquisition(e.r);

        out = [out; row]; %#ok<AGROW>
    end
end

% Sort output by (cell, run_index) for a stable, human-readable order
if ~isempty(out)
    [~, ord] = sortrows([out{:,1}, out{:,4}]);
    out = out(ord, :);
end

if exist(Split_template, 'file'), delete(Split_template); end
if ~isempty(out)
    writetable(out, Split_template);
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
