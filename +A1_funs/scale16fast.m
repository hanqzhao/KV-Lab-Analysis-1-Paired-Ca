% Faster version of scale16 to use when necessary
function scaled = scale16fast(image)
    image(image < 0) = 0;
    image = image - min(image(:)); % Subtracting the minimum value, which will now be zero
    scaled = image .* (65535 / max(image(:))); % Multiplying all values to 65535/max
end
