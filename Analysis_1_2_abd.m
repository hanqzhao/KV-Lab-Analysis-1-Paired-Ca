%% Define input parameters

clearvars -except select_f Analysis_template;
close all;

import A1_funs.*;

% Define the name of the maximum projection file
% Use Max_img_combined.tif (from Stage 1_1b) so paired runs share a mask
fname = 'Max_img_combined.tif';

% The template spreadsheet
if ~exist('Analysis_template', 'var')
    Analysis_template = 'Analysis_1_template_new.xlsx';
end

% Select which lines to do from the Excel Analysis template
if ~exist('select_f', 'var')
    select_f = 2;
end

% Adaptive thresholding parameters
adaptive_threshold = 0.4; % default = 0.3
w = 15; % the window size for adaptive thresholding, odd number >= 3

% weighting between inverted max proj and inverted distance transform
weight = 0.8; % default = 0.8

% parameter for minima detection for watershed separation
h = 0.02; % default = 0.02

input_list = readtable(Analysis_template, 'VariableNamingRule', 'preserve');

tracker = 1;
for f = select_f - 1
    fprintf('Analysing image %d of %d\n', tracker, length(select_f));

    %% READING THE MAX PROJECTION
    folder = char(input_list.(2)(f));
    run_name = char(input_list.(3)(f));

    % Input folders
    stage3_folder = ['Stage_3_A1/', folder, '/', num2str(run_name), '/'];
    stage2_folder = ['Stage_2b_cross_aligned/', folder, '/', num2str(run_name), '/'];

    % Read max projection from Stage_3_A1
    FNAME = fullfile(stage3_folder, fname);

    t1 = tic;

    I = imread(FNAME);
    
    % Normalise between 0 and 1
    I_norm = double(I) / 65535;

    %% ACTIVE BOUTON DETECTION

    fprintf('Active bouton detection and saving metadata...')
    
    % Adaptive thresholding
    adaptive_thresh = adaptthresh(I_norm, adaptive_threshold, 'NeighborhoodSize', [w w]);
    binary_mask = I_norm > adaptive_thresh;
    
    % Cleaning the mask
    se = strel('disk', 2);
    binary_mask = imopen(binary_mask, se);
    binary_mask = imclose(binary_mask, se);

    % Getting image of valleys
    I_comp = 1 - I_norm;
    dist_transform = bwdist(~binary_mask);
    I_combined = weight * I_comp + (1 - weight) * (1 - mat2gray(dist_transform));
    
    % Minima suppression using watershed
    I_min = imhmin(I_combined, h);
    watershed_mask = watershed(I_min);
    binary_mask(watershed_mask == 0) = 0;

    %% SAVING THE MASKS
    
    % save mask to Stage_3_A1
    imwrite(binary_mask, fullfile(stage3_folder, 'mask.tif'));
    
    % categorise each bouton in mask
    [labeledMask, numShapes] = bwlabel(binary_mask);
    
    % define folder to save individual shapes
    mask_folder = fullfile(stage3_folder, 'boutons/');
    
    if ~exist(mask_folder, 'dir')
        mkdir(mask_folder);
    end
    
    % Delete all files in the folder before writing new ones
    delete(fullfile(mask_folder, '*.*'));
    
    % save each shape
    for k = 1:numShapes
        individualMask = (labeledMask == k);
        imwrite(individualMask, fullfile(mask_folder, sprintf('bouton_%d.tif', k)));
    end

    %% SAVING BOUTON PARAMETERS
    
    % Get region properties for all labeled shapes
    stats = regionprops(labeledMask, 'Area', 'Centroid', 'MajorAxisLength', 'MinorAxisLength', 'BoundingBox');

    % Extract boundaries of each shape
    boundaries = bwboundaries(labeledMask);
    
    % Compute stats
    num_shapes = numel(stats);
    centroid_coords = vertcat(stats.Centroid);
    areas = vertcat(stats.Area);
    major_axes = vertcat(stats.MajorAxisLength);
    minor_axes = vertcat(stats.MinorAxisLength);
    
    % Initialize distance matrix
    distance_matrix = zeros(num_shapes, num_shapes);

    for i = 1:num_shapes
        for j = 1:num_shapes
            if i ~= j
                boundary_i = boundaries{i};
                boundary_j = boundaries{j};
                all_distances = pdist2(boundary_i, boundary_j);
                min_distance = min(all_distances(:));
                distance_matrix(i,j) = min_distance;
            else
                distance_matrix(i,j) = Inf;
            end
        end
    end
    
    % Prepare results array
    results = zeros(num_shapes, 9);
    
    for i = 1:num_shapes
        [min_dist, nearest_neighbor_idx] = min(distance_matrix(i,:));
        centroid_dist = norm(centroid_coords(i,:) - centroid_coords(nearest_neighbor_idx,:));
        
        results(i,:) = [i, ...
                        stats(i).Area, ...
                        major_axes(i), ...
                        minor_axes(i), ...
                        centroid_coords(i,1), ...
                        centroid_coords(i,2), ...
                        nearest_neighbor_idx, ...
                        min_dist, ...
                        centroid_dist];
    end
    
    column_names = {'Bouton_Number', 'Area', 'Major_Axes', 'Minor_Axes', 'Centroid_X', 'Centroid_Y', 'Nearest_Neighbor_Index', 'Minimum_Distance', 'Centroid_Distance'};
    
    output_file = fullfile(stage3_folder, 'bouton_metadata.csv');
    csvwrite_with_headers(output_file, results, column_names);

    t1 = toc(t1);
    fprintf('done. ')
    fprintf('%f seconds\n', t1)

    %% LOADING IMAGE STACK (aligned from Stage 2)

    fprintf('Loading image stack...')
    t2 = tic;
    
    IFNAME = fullfile(stage2_folder, 'aligned.tif');

    info = imfinfo(IFNAME);
    dim1 = info(1).Height;
    dim2 = info(1).Width;
    dim3 = length(info);
    imageStack_temp = zeros(dim1, dim2, dim3, 'uint16');
    parfor k = 1:dim3
        currentImage = imread(IFNAME, k, 'Info', info);
        imageStack_temp(:, :, k) = currentImage;
    end
    t2 = toc(t2);
    fprintf('done. ')
    fprintf('%f seconds\n', t2);

    %% SAVING MEAN TRACES

    fprintf('Extracting mean traces and rings...')
    t3 = tic;

    % Initialize mean traces table
    traces = zeros(dim3, numShapes);
    
    for t = 1:dim3
        img_current = imageStack_temp(:,:,t);
        
        for shape_id = 1:numShapes
            shape_pixels = labeledMask == shape_id;
            shape_values = img_current(shape_pixels);
            traces(t, shape_id) = mean(shape_values);
        end
    end

    col_names = arrayfun(@(i) sprintf('bouton_%d', i), 1:numShapes, 'UniformOutput', false);
    traces_table = array2table(traces, 'VariableNames', col_names);
    
    output_filename = fullfile(stage3_folder, 'mean_traces.csv');
    writetable(traces_table, output_filename, 'WriteRowNames', false);
    
    % Save the plots in a separate folder
    plot_folder = fullfile(stage3_folder, 'bouton_plots');
    if ~exist(plot_folder, 'dir')
        mkdir(plot_folder);
    end

    fig_folder = fullfile(stage3_folder, 'bouton_figs');
    if ~exist(fig_folder, 'dir')
        mkdir(fig_folder);
    end

    % Delete all files in the folder before writing new ones
    delete(fullfile(plot_folder, '*.*'));
    delete(fullfile(fig_folder, '*.*'));

    for i = 1:width(traces_table)
        trace = traces_table{:, i};
        
        figure('Position', [100, 100, 1200, 150]);
        plot(trace);
        xlabel('Frame');
        ylabel('Amplitude');
        xlim tight
        
        saveas(gcf, fullfile(plot_folder, ['bouton_' num2str(i) '.png']));
        savefig(fullfile(fig_folder, ['bouton_', num2str(i), '.fig']));
        
        close;
    end
    
    t3 = toc(t3);
    fprintf('done. ')
    fprintf('%f seconds\n', t3)

    %% Visualising image
    
    figure('Position', [500, 500, dim2, dim1]);

    imshow(I_norm);
    colormap(fire)
    hold on;

    for k = 1:length(boundaries)
        boundary = boundaries{k};
        plot(boundary(:,2), boundary(:,1), 'Color', [1 1 0], 'LineWidth', 0.5);
    end

    for i = 1:numel(stats)
        cent = stats(i).Centroid;
        bbox = stats(i).BoundingBox;
        offset_x = bbox(3) * 0.8;
        offset_y = -bbox(4) * 0.8;

        text(cent(1) + offset_x, cent(2) + offset_y, num2str(i), ...
            'Color', 'yellow', ...
            'FontSize', 5, ...
            'HorizontalAlignment', 'center');
    end

    hold off;

    print(gcf, fullfile(stage3_folder, 'bouton_visualisation.tif'), '-dtiff', '-r600');
    savefig(fullfile(stage3_folder, 'bouton_visualisation.fig'));
    close;

    tracker = tracker + 1;

    disp(['Total no. of boutons: ', num2str(numShapes)]);
    disp('Image finished')
    disp('.....')
end

disp('All analysis done.')
