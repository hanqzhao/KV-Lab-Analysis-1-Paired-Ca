%% Check if mat file exists

clearvars -except select_f Analysis_template;
close all;

% Check if the MAT file exists
mat_file = 'Analysis_1_Results.mat';

if exist(mat_file, 'file')
    % Load existing Results structure
    load(mat_file);
    fprintf('Loaded existing Results structure from %s\n', mat_file);
else
    % Create Results structure from scratch
    fprintf('File not found. Creating new Results structure...\n');

    f1 = 'Folder'; value1 = {[]};
    f2 = 'Run_name'; value2 = {[]};
    f3 = 'Run_index'; value3 = {[]};
    f4 = 'Imaged_area_index'; value4 = {[]};
    f5 = 'Paradigm'; value5 = {[]};
    f6 = 'Acquisition'; value6 = {[]};
    f7 = 'Frame_data'; value7 = struct;
    f8 = 'AP_data'; value8 = struct;
    f9 = 'Bouton_metadata'; value9 = struct;
    f10 = 'Bouton'; value10 = struct;
    f11 = 'Bouton_rings'; value11 = struct;
    f12 = 'Calcium_mM'; value12 = {[]};

    Results_A1 = struct(f1, value1, f2, value2, f3, value3, f4, value4, ...
                     f5, value5, f6, value6, f7, value7, f8, value8, ...
                     f9, value9, f10, value10, f11, value11, f12, value12);

    Results_A1(200).Folder = f1;

    % Save the newly created file
    save(mat_file, 'Results_A1');
    fprintf('New Results structure saved as %s\n', mat_file);
end

% The template spreadsheet
if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template.xlsx';
end
input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');

% Select which lines to do from the Excel Analysis template
if ~exist('select_f', 'var')
    select_f = 2;
end

tracker = 1;

% --- Error tracking ---
error_log = struct('row', {}, 'folder', {}, 'run_name', {}, 'message', {}, 'stack', {});

for f = select_f - 1
    fprintf('Analysing image %d of %d\n', tracker, length(select_f));

    try
        % Extract relevant data from input_list
        select_f_cells = input_list{f, 1};
        Folder = string(input_list{f, 2});
        check_run = input_list{f, 4};
        acquisition_mode = input_list{f, 7};

        % Input folder from Stage_3_A1
        run_name = char(input_list{f, 3});
        stage3_folder = ['Stage_3_A1/', char(Folder), '/', run_name, '/'];

        % Load metadata from Stage_3_A1
        metadata_folder = fullfile(stage3_folder, 'bouton_metadata.csv');
        metadata = readtable(metadata_folder);
        metadata = metadata{:, :};

        % Print folder information
        fprintf('Folder = %s, run = %i \n', Folder, check_run);

        % Find matching run index in Results
        match_index = find(Results_A1(select_f_cells).Run_index == check_run);

        % Parse calcium concentration (mM) from the run name. The run-name
        % convention for this paradigm is <ROI>_<run>_<Ca>mM; if the suffix
        % is absent or malformed, NaN is stored.
        ca_token = regexp(run_name, '(\d+)mM', 'tokens', 'once');
        if isempty(ca_token)
            calcium_mM = NaN;
        else
            calcium_mM = str2double(ca_token{1});
        end

        if ~isempty(match_index)
            Results_A1(select_f_cells).Run_name{match_index} = string(run_name);
            Results_A1(select_f_cells).Run_index(match_index) = check_run;
            Results_A1(select_f_cells).Imaged_area_index(match_index) = input_list{f, 5};
            Results_A1(select_f_cells).Paradigm(match_index) = input_list{f, 6};
            Results_A1(select_f_cells).Acquisition(match_index) = input_list{f, 7};
            Results_A1(select_f_cells).Calcium_mM(match_index) = calcium_mM;
        else
            if check_run > length(Results_A1(select_f_cells).Run_index)
                Results_A1(select_f_cells).Run_name{check_run} = "";
                Results_A1(select_f_cells).Run_index(check_run) = 0;
                Results_A1(select_f_cells).Imaged_area_index(check_run) = 0;
                Results_A1(select_f_cells).Paradigm(check_run) = 0;
                Results_A1(select_f_cells).Acquisition(check_run) = 0;
                Results_A1(select_f_cells).Calcium_mM(check_run) = NaN;
            end

            Results_A1(select_f_cells).Run_name{check_run} = string(run_name);
            Results_A1(select_f_cells).Run_index(check_run) = check_run;
            Results_A1(select_f_cells).Imaged_area_index(check_run) = input_list{f, 5};
            Results_A1(select_f_cells).Paradigm(check_run) = input_list{f, 6};
            Results_A1(select_f_cells).Acquisition(check_run) = input_list{f, 7};
            Results_A1(select_f_cells).Calcium_mM(check_run) = calcium_mM;
        end

        % Update Results structure with new or modified data
        Results_A1(select_f_cells).Folder = Folder;

        % Load ROI data from Stage_3_A1
        ROI = fullfile(stage3_folder, 'mean_traces.csv');
        ROI_data = readtable(ROI);
        ROI_data = ROI_data{:, :};

        % Store ROI data in Results
        Results_A1(select_f_cells).Bouton(input_list{f, 4}).data = [(1:size(ROI_data, 1))' ROI_data];

        % Store metadata in Results
        Results_A1(select_f_cells).Bouton_metadata(input_list{f, 4}).data = metadata;

        % Load raw data (.mat) from Stage_3_A1
        raw_data = fullfile(['Stage_3_A1/', char(Folder), '/'], [run_name, '.mat']);

        if acquisition_mode
            run Calculation_Unit_Module_Analysis_1_4_new;
        else
            run Calculation_Unit_Module_Analysis_1_4_old;
        end

        % Store frame data in Results
        Results_A1(select_f_cells).Frame_data(input_list{f, 4}).data = FRAME_DATA;

        % Adjust AP_data_matrix if necessary
        if length(ROI_data) ~= length(FRAME_DATA{1})
            AP_data_matrix = [AP_data_matrix, AP_data_matrix(:, 2) - 1];
        else
            AP_data_matrix = [AP_data_matrix, AP_data_matrix(:, 2)];
        end
        AP_DATA{1, 1} = AP_data_matrix;

        % Store AP data in Results
        Results_A1(select_f_cells).AP_data(input_list{f, 4}).data = AP_DATA;

        % Load rings data from Stage_3_A1
        rings_file = fullfile(stage3_folder, 'mean_traces_plus_rings.mat');
        if exist(rings_file, 'file')
            rings_data = load(rings_file);
            rings_data = rings_data.ring_incl_centre;
        else
            rings_data = struct();
        end

        Results_A1(select_f_cells).Bouton_rings(input_list{f, 4}).data = rings_data;

        % Save Results to base folder
        save('Analysis_1_Results', 'Results_A1');

    catch ME
        % Store the error details
        cur_folder = '';
        cur_run = '';
        try
            cur_folder = char(input_list{f, 2});
            cur_run = char(input_list{f, 3});
        catch
            % If even reading the identifiers fails, leave them blank
        end

        error_log(end+1) = struct( ...
            'row',      f + 1, ...
            'folder',   cur_folder, ...
            'run_name', cur_run, ...
            'message',  ME.message, ...
            'stack',    ME.stack);
        fprintf('  *** ERROR on row %d: %s\n', f + 1, ME.message);

        % Still save Results so progress from successful rows is not lost
        save('Analysis_1_Results', 'Results_A1');
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
    save('A1_4_error_log.mat', 'error_log');
    fprintf('Error log saved to results_error_log.mat\n');
end

disp('All analysis done.');
