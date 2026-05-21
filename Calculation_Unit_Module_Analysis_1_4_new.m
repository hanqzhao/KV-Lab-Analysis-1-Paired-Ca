close all;

% load("EM241027_EM241011_Hippo_Pup2_Cvslp2_Cell2_roi1.mat");
load(raw_data);

%% Define parameters

voltage_threshold_fraction = 0.3; % fraction value of min of V trace to determine true AP and avoid capacitance transient

Istep_duration_scale = 3; % scaling factor - how long after the current step for identifying peaks

%% Indentifying frame information based on camera trigger and camera exposure

% Thresholding camera trigger
D = Y(:, 4) >= 0.5 * (max(Y(:, 4)) - min(Y(:, 4)));

% camera trigger segments
diff_D = diff([0; D; 0]); % Pad with zeros to handle edge cases
trigger_starts = find(diff_D == 1); % Indices where segments start

% camera exposure
C = Y(:, 3) >= 0.5 * (max(Y(:, 3)) - min(Y(:, 3)));

% camera exposure segments
diff_C = diff([0; C; 0]);
exp_starts = find(diff_C == 1);
exp_ends = find(diff_C == -1) - 1;

% Working out durations of each frame - given by the difference between
% trigger starts
durations = diff(trigger_starts);
durations(durations > 100) = 0; % pick out gaps in the acquisition
durations = [durations; 0]; % last frame as well
mean_duration = mean(durations(durations ~= 0));
durations(durations == 0) = round(mean_duration); % set all gaps to mean duration

% frame ends - given by the trigger starts and duration
frame_ends = trigger_starts + durations - 1;

output_frames = [(1:size(durations, 1))', trigger_starts, frame_ends, durations];

% in real time — clamp frame_ends+1 so the last frame doesn't exceed T
next_idx = min(frame_ends + 1, length(T));
output_frames = [output_frames, ...
              T(trigger_starts), T(frame_ends), ...
              T(next_idx) - T(trigger_starts)];

mean_period = mean(output_frames(:, 4));
mean_period_real = mean(output_frames(:, 7));

% t1 - time until last line starts exposing
t1 = exp_starts - trigger_starts;

% t2 - total exposure time for each line
t2 = exp_ends - trigger_starts;

output_frames = [output_frames, t1, t2];
output_frames = [output_frames, T(t1), T(t2)];

mean_t1 = mean(t1);
mean_t2 = mean(t2);
mean_t1_real = mean(output_frames(:, 10));
mean_t2_real = mean(output_frames(:, 11));

%% combine into FRAME_DATA

FRAME_DATA{1, 1} = output_frames;
FRAME_DATA{1, 2} = mean_period_real;
FRAME_DATA{1, 3} = mean_t1_real;
FRAME_DATA{1, 4} = mean_t2_real;

%% plotting

vector_indices = 1:1:length(C);

% f1 = figure(1);
% fig1(1) = subplot(3, 1, 1);
% plot(vector_indices, C);
% hold on;
% plot(vector_indices, D);
% ylim([-0.5, 1.5]);
% plot(output_frames(:, 2), 1, 'ro')
% plot(output_frames(:, 3), 1, 'ko')
% plot(exp_starts, 1, 'r*')
% plot(exp_ends, 1, 'r*')
% 
% f2 = figure(2); % in real time
% fig2(1) = subplot(3, 1, 1);
% plot(T, C);
% hold on;
% plot(T, D);
% ylim([-0.5, 1.5]);
% plot(output_frames(:, 5), 1, 'ro')
% plot(output_frames(:, 6), 1, 'ko')
% plot(T(exp_starts), 1, 'r*')
% plot(T(exp_ends), 1, 'r*')

%% Indentifying indeces of starting and ending of the current step and its duration

% Normalize and thresholding
Y_norm = Y(:, 2) - min(Y(:, 2));
I = Y_norm >= 0.5 * max(Y_norm);

% Find transitions (where the signal crosses the threshold)
diff_I = diff([0; I; 0]);
I_starts = find(diff_I == 1);  % Start indices of intervals
I_ends = find(diff_I == -1) - 1;       % End indices of intervals

% Calculate durations
I_dur = I_ends - I_starts;

% Combine results into output matrix
output_current_frames = [(1:size(I_dur, 1))', I_starts, I_ends, I_dur];

% Compute mean duration
current_duration = mean(I_dur);

% figure(1);
% fig1(2) = subplot(3, 1, 2);
% plot(vector_indices, I, 'k');
% hold on;
% plot(output_current_frames(:, 2), 1, 'r*');
% plot(output_current_frames(:, 3), 1, 'r*');
% ylim([-0.5 1.5]);
% 
% figure(2);
% title('Plotted in real time');
% fig2(2) = subplot(3, 1, 2);
% plot(T, I, 'k');
% hold on;
% plot(T(output_current_frames(:, 2)), 1, 'r*');
% plot(T(output_current_frames(:, 3)), 1, 'r*');
% ylim([-0.5 1.5]);

%% Indetifying peaks of voltage

% Extract voltage data
V = Y(:, 1);

% Define voltage threshold
voltage_threshold = min(V) * voltage_threshold_fraction;

% Identify voltage values below threshold
V_below_threshold = V .* (V <= voltage_threshold);

% Preallocate voltage_pks
voltage_pks = zeros(length(output_current_frames), 3);
valid_indices = false(length(output_current_frames), 1);

% Find minima (peaks) in voltage signal
for k = 1:length(output_current_frames)
    start_idx = output_current_frames(k, 2);
    end_idx = min(start_idx + round(current_duration * Istep_duration_scale), length(V));
    temp = V_below_threshold(start_idx:end_idx);
    
    if any(temp)
        [pks, loc] = min(temp);
        voltage_pks(k, :) = [k, loc + start_idx - 1, pks];
        valid_indices(k) = true;
    end
end

% Remove unused rows
voltage_pks = voltage_pks(valid_indices, :);

%% Identifying frame index for each AP and saving AP_DATA

% Associate minima with frame indices
AP_data_matrix = zeros(size(voltage_pks, 1), 4);
valid_AP = true(size(voltage_pks, 1), 1);
for k = 1:size(voltage_pks, 1)
    idx = find(output_frames(:, 2) >= voltage_pks(k, 2), 1);
    if isempty(idx)
        warning('AP at sample %d occurs after the last frame trigger — skipped.', voltage_pks(k, 2));
        valid_AP(k) = false;
        continue;
    end
    frame_idx = idx - 1;
    AP_data_matrix(k, :) = [k, frame_idx, voltage_pks(k, 2), T(voltage_pks(k, 2))];
end
AP_data_matrix = AP_data_matrix(valid_AP, :);

% Add voltage values
AP_data_matrix = [AP_data_matrix, voltage_pks(valid_AP, 3)];

% Store results
AP_DATA{1, 1} = AP_data_matrix;

%% plotting

% figure(1);
% fig1(3) = subplot(3, 1, 3);
% plot(vector_indices, V);
% hold on;
% plot(voltage_pks(:, 2), voltage_pks(:, 3), 'k*');
% 
% figure(2);
% fig2(3) = subplot(3, 1, 3);
% plot(T, V);
% hold on;
% plot(T(voltage_pks(:, 2)), voltage_pks(:, 3), 'k*');
% 
% linkaxes(fig1, 'x'); % Synchronize limits of specified 2-D axes
% linkaxes(fig2, 'x'); % Synchronize limits of specified 2-D axes
% 
% movegui(f1, 'northeast');
% movegui(f2, 'east');
