close all;

% Note - PM format of electrophys files, e.g. 51.mat
% T - time
% Y(:,1) - Voltage
% Y(:,2) - Current
% Y(:,3) - Frames

% load 51.mat %can be used to run with a particular file to check APs only
% load("EM_190301_1/EM_190301_1_3_ParY_2.mat");
load(raw_data);

%% Define parameters

voltage_threshold_fraction = 0.3; % fraction value of min of V trace to determine true AP and avoid capacitance transient

Istep_duration_scale = 3; % scaling factor - how long after the current step for identifying peaks

%% Indentifying indeces of opening and closing the frames and saved in output_frames as [numbering start_index end_index_midpoint_index]

% Thresholding
C = Y(:, 3) >= 0.5 * (max(Y(:, 3)) - min(Y(:, 3)));

% Find start and end indices of segments
diff_C = diff([0; C; 0]); % Pad with zeros to handle edge cases
starts = find(diff_C == 1); % Indices where segments start
ends = find(diff_C == -1) - 1; % Indices where segments end

% Calculate midpoints and durations
midpoints = starts + round(0.5 * (ends - starts)); % Midpoints
durations = ends - starts + 1; % Durations in indices

% Combine into output_frames
output_frames = [(1:size(durations, 1))', starts, ends, midpoints, durations];

% Convert to real time using time vector T — clamp ends+1 so the last frame doesn't exceed T
next_idx = min(ends + 1, length(T));
output_frames = [output_frames, ...
                 T(starts), T(ends), T(midpoints), ...
                 T(next_idx) - T(starts)]; % Duration in real time

%% Identifying periods

M = size(output_frames, 1); % Number of frames

% Preallocate frames_periods
frames_periods = zeros(M, 3);

% First frame
midpoint_start_frame = output_frames(1, 2) - round(0.5 * (output_frames(2, 2) - output_frames(1, 3)));
midpoint_end_frame = output_frames(1, 3) + round(0.5 * (output_frames(2, 2) - output_frames(1, 3)));
frames_periods(1, :) = [1, midpoint_start_frame + 1, midpoint_end_frame];

% Middle frames
for k = 2:M - 1
    midpoint_start_frame = output_frames(k - 1, 3) + round(0.5 * (output_frames(k, 2) - output_frames(k - 1, 3)));
    midpoint_end_frame = output_frames(k, 3) + round(0.5 * (output_frames(k + 1, 2) - output_frames(k, 3)));
    frames_periods(k, :) = [k, midpoint_start_frame + 1, midpoint_end_frame];
end

% Last frame
midpoint_start_frame = frames_periods(M - 1, 3);
midpoint_end_frame = output_frames(M, 3) + round(0.5 * (output_frames(M, 2) - output_frames(M - 1, 3)));
frames_periods(M, :) = [M, midpoint_start_frame + 1, midpoint_end_frame];

% Add duration in indices
frames_periods = [frames_periods, frames_periods(:, 3) + 1 - frames_periods(:, 2)];

% Add real-time values — clamp period_end+1 so the last frame doesn't exceed T
next_period_idx = min(frames_periods(:, 3) + 1, length(T));
frames_periods = [frames_periods, ...
                  T(frames_periods(:, 2)), ... % Start time
                  T(frames_periods(:, 3)), ... % End time
                  T(next_period_idx) - T(frames_periods(:, 2))]; % Duration in real time

%% combining into FRAME_DATA

FRAME_DATA{1, 1} = [frames_periods output_frames(:, 2:end)];
FRAME_DATA{1, 2} = median(frames_periods(:, 7)); % median duration in real time

%% plotting

vector_indices = 1:1:length(C);

% f1 = figure(1);
% fig1(1) = subplot(3, 1, 1);
% plot(vector_indices, C);
% hold on;
% plot(output_frames(:, 2), 1, 'r*');
% plot(output_frames(:, 3), 1, 'r*');
% plot(frames_periods(:, 2), 0, 'ro');
% plot(frames_periods(:, 3), 0, 'ko');
% ylim([-0.5 1.5]);
%
% f2 = figure(2); % in real time
% fig2(1) = subplot(3, 1, 1);
% plot(T, C);
% hold on;
% plot(T(output_frames(:, 2)), 1, 'r*');
% plot(T(output_frames(:, 3)), 1, 'r*');
% plot(T(frames_periods(:, 2)), 0, 'ro');
% plot(T(frames_periods(:, 3)), 0, 'ko');
% ylim([-0.5 1.5]);

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
    idx = find(frames_periods(:, 2) >= voltage_pks(k, 2), 1);
    if isempty(idx)
        warning('AP at sample %d occurs after the last frame period — skipped.', voltage_pks(k, 2));
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
