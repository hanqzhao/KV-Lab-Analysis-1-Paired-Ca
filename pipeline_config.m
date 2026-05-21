%% pipeline_config.m — Edit this file before running the pipeline.
%
% run_pipeline.m reads this file to get the settings for each stage.
% All paths are relative to the directory where you run MATLAB.

% ============================================================
% EXPERIMENT TYPE
% Which stage-0_1 concatenation script to use.
% Options: 'EM_707', 'EM_825', 'VAMP'
% ============================================================

experiment = 'VAMP';

% ============================================================
% EXCEL ROWS TO PROCESS
% Excel row numbers (row 1 = header).
% Examples: 2 (one cell), 2:10 (a range), [2 5 9] (specific rows)
% ============================================================

select_f = 2;

% ============================================================
% TEMPLATE SPREADSHEET
% The Excel file that lists all experiments to process.
% All stages read from this file.
% ============================================================

Analysis_template = 'Analysis_1_template_new.xlsx';

% ============================================================
% STAGE SWITCHES
% Set to false to skip a stage when re-running part of the pipeline.
% ============================================================

run_stage_0_1  = false;
run_stage_0_2  = false;
run_stage_0_3  = false;   % cross-run alignment (calcium paradigm)
run_stage_1_1  = false;
run_stage_1_1b = false;   % combined max projection across paired runs
run_stage_1_2  = false;
run_stage_1_4  = true;
