%% run_pipeline.m — Master driver for the A1 iGluSnFR analysis pipeline
%
% USAGE
%   1. Edit pipeline_config.m to set experiment, select_f,
%      Analysis_template, and which stages to run.
%   2. Run this script (F5), or run individual %% sections in MATLAB.
%
% STAGE ORDER
%   0_1   Concatenation       raw wcp + tif      ->  Stage_1_organised
%   0_2   Alignment           Stage_1_organised  ->  Stage_2_aligned
%   0_3   Cross-run alignment Stage_2_aligned    ->  Stage_2b_cross_aligned
%   1_1   Filtering           Stage_2b_cross_aligned -> Stage_3_A1 (filtered + max proj)
%   1_1b  Combined max proj   Stage_3_A1 (per-run max -> per-ROI Max_img_combined.tif)
%   1_2   Bouton detection    Stage_3_A1 (combined max -> masks + per-run traces)
%   1_4   Merge results       Stage_3_A1         ->  Analysis_1_Results.mat

clearvars;
close all;
clc;

% Load all settings from pipeline_config.m
run pipeline_config;

% Persist config to a temp file so each stage can restore it after its
% own clearvars call (stages use 'clearvars -except select_f Analysis_template').
save('_pipeline_cfg.mat', 'select_f', 'experiment', 'Analysis_template', ...
     'run_stage_0_1', 'run_stage_0_2', 'run_stage_0_3', ...
     'run_stage_1_1', 'run_stage_1_1b', 'run_stage_1_2', 'run_stage_1_4');

fprintf('==========================================================\n');
fprintf(' A1 pipeline starting\n');
fprintf(' Experiment: %s | Template: %s | Rows: %s\n', ...
        experiment, Analysis_template, mat2str(select_f));
fprintf('==========================================================\n\n');

%% Stage 0_1 — Concatenation

load('_pipeline_cfg.mat');
if run_stage_0_1
    fprintf('\n--- Stage 0_1: Concatenation (%s) ---\n', experiment);
    switch experiment
        case 'EM_707'; run Analysis_0_1_concatenation_EM_707;
        case 'EM_825'; run Analysis_0_1_concatenation_EM_825;
        case 'VAMP';   run Analysis_0_1_concatenation_VAMP;
        otherwise;     error('Unknown experiment_type ''%s''. Use EM_707, EM_825, or VAMP.', experiment);
    end
end

%% Stage 0_2 — Alignment

load('_pipeline_cfg.mat');
if run_stage_0_2
    fprintf('\n--- Stage 0_2: Alignment ---\n');
    run Analysis_0_2_alignment;
end

%% Stage 0_3 — Cross-run alignment (calcium paradigm)

load('_pipeline_cfg.mat');
if run_stage_0_3
    fprintf('\n--- Stage 0_3: Cross-run alignment ---\n');
    run Analysis_0_3_cross_run_alignment;
end

%% Stage 1_1 — Filtering and max projection

load('_pipeline_cfg.mat');
if run_stage_1_1
    fprintf('\n--- Stage 1_1: Filtering and max projection ---\n');
    run Analysis_1_1_max_proj;
end

%% Stage 1_1b — Combined max projection across paired runs

load('_pipeline_cfg.mat');
if run_stage_1_1b
    fprintf('\n--- Stage 1_1b: Combined max projection ---\n');
    run Analysis_1_1b_combined_max;
end

%% Stage 1_2 — Active bouton detection

load('_pipeline_cfg.mat');
if run_stage_1_2
    fprintf('\n--- Stage 1_2: Active bouton detection ---\n');
    run Analysis_1_2_abd;
end

%% Stage 1_4 — Merge results

load('_pipeline_cfg.mat');
if run_stage_1_4
    fprintf('\n--- Stage 1_4: Merging results ---\n');
    run Analysis_1_4_merging_data;
end

%% Done

load('_pipeline_cfg.mat');
delete('_pipeline_cfg.mat');

fprintf('\n==========================================================\n');
fprintf(' Pipeline complete — rows: %s\n', mat2str(select_f));
fprintf('==========================================================\n');
