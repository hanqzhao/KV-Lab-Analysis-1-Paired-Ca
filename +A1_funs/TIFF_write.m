% Fast writing of image stack
function TIFF_write(filename, imgData)
    % filename: string, name of the TIFF file to save
    % imgData: 3D array, with dimensions [height, width, numFrames]

    % Check if input array is a 3D matrix
    if ndims(imgData) ~= 3
        error('Input image data must be a 3D array');
    end

    % Get image dimensions
    [height, width, numFrames] = size(imgData);

    % Initialize the Tiff object for writing
    t = Tiff(filename, 'w8');

    % Loop over each frame in the 3D array
    for i = 1:numFrames
        % Set the tag properties for each image slice
        t.setTag('ImageLength', height);
        t.setTag('ImageWidth', width);
        t.setTag('Photometric', Tiff.Photometric.MinIsBlack);
        t.setTag('BitsPerSample', 16);
        t.setTag('SamplesPerPixel', 1);
        t.setTag('Compression', Tiff.Compression.None);
        t.setTag('PlanarConfiguration', Tiff.PlanarConfiguration.Chunky);

        % Write the frame to the TIFF file
        t.write(imgData(:, :, i));

        % If this is not the last frame, add a new page
        if i < numFrames
            t.writeDirectory();
        end
    end

    % Close the Tiff object
    t.close();
end
