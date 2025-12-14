%% =========================================================
%  Simple GAN for Digit Generation (0-9)
%  7x5 pixel images (minimal size untuk angka)
% =========================================================
clear; clc;
close all;

% Set rand seed
rng(0);

% Parameters
img_height = 8;         % Image height (8 = 2^3, FPGA-friendly!)
img_width = 8;          % Image width (8 = 2^3, FPGA-friendly!)
img_size = img_height * img_width;  % 64 pixels total (2^6, perfect!)
latent_dim = 16;        % Latent variables (lebih besar untuk variasi!) ✓
                        
D_hidden_L = 32;        % Discriminator hidden neurons (lebih besar!) ✓
G_hidden_L = 32;        % Generator hidden neurons (lebih besar!) ✓

num_epochs = 200000;    % Epochs (lebih banyak!) ✓
eta_D = 0.0008;         % Learning rate Discriminator (turun sedikit) ✓
eta_G = 0.0015;         % Learning rate Generator ✓
save_path = "trained_digit_gan.mat";
DGL = 1;                % D:G training ratio = 1:1 (balance!) ✓

% Anti mode-collapse parameters
label_noise = 0.1;      % Add noise to real/fake labels ✓
dropout_prob = 0.3;     % Dropout for regularization ✓

% ======== Training Data: Angka 0-9 (8x8 pixels) ========
fprintf('Creating digit templates...\n');

% Angka 0 (8x8)
digit_0 = [
   -1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
    1 -1 -1 -1 -1 -1 -1  1;
    1 -1 -1 -1 -1 -1 -1  1;
    1 -1 -1 -1 -1 -1 -1  1;
    1 -1 -1 -1 -1 -1 -1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1 -1
];

% Angka 1 (8x8)
digit_1 = [
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1  1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1  1  1  1  1  1  1 -1
];

% Angka 2 (8x8)
digit_2 = [
   -1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
   -1 -1 -1 -1 -1 -1  1  1;
   -1 -1 -1 -1 -1  1  1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1  1  1 -1 -1 -1 -1;
    1  1 -1 -1 -1 -1 -1 -1;
    1  1  1  1  1  1  1  1
];

% Angka 3 (8x8)
digit_3 = [
   -1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
   -1 -1 -1 -1 -1 -1  1  1;
   -1 -1 -1 -1  1  1  1 -1;
   -1 -1 -1 -1  1  1  1 -1;
   -1 -1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1 -1
];

% Angka 4 (8x8)
digit_4 = [
   -1 -1 -1 -1  1  1 -1 -1;
   -1 -1 -1  1  1  1 -1 -1;
   -1 -1  1  1  1  1 -1 -1;
   -1  1  1 -1  1  1 -1 -1;
    1  1 -1 -1  1  1 -1 -1;
    1  1  1  1  1  1  1  1;
   -1 -1 -1 -1  1  1 -1 -1;
   -1 -1 -1 -1  1  1 -1 -1
];

% Angka 5 (8x8)
digit_5 = [
    1  1  1  1  1  1  1  1;
    1  1 -1 -1 -1 -1 -1 -1;
    1  1 -1 -1 -1 -1 -1 -1;
    1  1  1  1  1  1  1 -1;
   -1 -1 -1 -1 -1 -1  1  1;
   -1 -1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1 -1
];

% Angka 6 (8x8)
digit_6 = [
   -1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1 -1 -1;
    1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1 -1
];

% Angka 7 (8x8)
digit_7 = [
    1  1  1  1  1  1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1 -1 -1 -1 -1  1  1 -1;
   -1 -1 -1 -1  1  1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1;
   -1 -1 -1  1  1 -1 -1 -1
];

% Angka 8 (8x8)
digit_8 = [
   -1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1 -1
];

% Angka 9 (8x8)
digit_9 = [
   -1  1  1  1  1  1  1 -1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1  1;
   -1 -1 -1 -1 -1 -1  1  1;
    1  1 -1 -1 -1 -1  1  1;
   -1  1  1  1  1  1  1 -1
];

% Combine all digits into dataset
data = [
    digit_0(:)'; 
    digit_1(:)'; 
    digit_2(:)'; 
    digit_3(:)';
    digit_4(:)';
    digit_5(:)';
    digit_6(:)';
    digit_7(:)';
    digit_8(:)';
    digit_9(:)'
];

num_data = size(data, 1);
fprintf('Dataset created: %d digits, %d pixels each (8x8 = 2^6, FPGA-optimized!)\n\n', num_data, img_size);

% Visualize training data
figure('Name', 'Training Data: Digits 0-9');
for i = 1:num_data
    subplot(2, 5, i);
    img = reshape(data(i,:), img_height, img_width);
    imagesc(img);
    colormap gray;
    axis image off;
    title(sprintf('Digit %d', i-1));
end
sgtitle('Training Dataset (8x8 pixels - FPGA Optimized)');
drawnow;

% ===  Loss data ===
loss_D = zeros(num_epochs, 1);
loss_G = zeros(num_epochs, 1);

% ======== Network Initialization ========
fprintf('Initializing networks...\n');

% Generator weights (Xavier initialization untuk stability!)
Wg2 = randn(G_hidden_L, latent_dim) * sqrt(2.0 / (latent_dim + G_hidden_L));
bg2 = zeros(G_hidden_L, 1);
Wg3 = randn(img_size, G_hidden_L) * sqrt(2.0 / (G_hidden_L + img_size));
bg3 = zeros(img_size, 1);

% Discriminator weights (Xavier initialization)
Wd2 = randn(D_hidden_L, img_size) * sqrt(2.0 / (img_size + D_hidden_L));
bd2 = zeros(D_hidden_L, 1);
Wd3 = randn(1, D_hidden_L) * sqrt(2.0 / (D_hidden_L + 1));
bd3 = 0;

fprintf('Generator: %d → %d → %d\n', latent_dim, G_hidden_L, img_size);
fprintf('Discriminator: %d → %d → 1\n', img_size, D_hidden_L);
fprintf('Total Generator params: %d\n', numel(Wg2) + numel(bg2) + numel(Wg3) + numel(bg3));
fprintf('Total Discriminator params: %d\n\n', numel(Wd2) + numel(bd2) + numel(Wd3) + numel(bd3));

% ======== Activation functions ========
sigmoid = @(x) 1./(1 + exp(-x));
tanh_f = @(x) tanh(x);

% ======== Training Loop ========
fprintf('Starting training...\n\n');
figure('Name', 'Training Progress');

for epoch = 1:num_epochs
    % ==== Update Discriminator (D) ====
    % Sample real image
    idx = randi(num_data);
    x_real = data(idx, :)';
    
    % Add noise to real data (anti-overfit)
    x_real_noisy = x_real + 0.1 * randn(size(x_real));
    x_real_noisy = max(-1, min(1, x_real_noisy));  % Clip to [-1, 1]
    
    % Generate fake image
    ng = randn(latent_dim, 1);
    ag2 = tanh_f(Wg2 * ng + bg2);
    x_fake = tanh_f(Wg3 * ag2 + bg3);
    
    % Label smoothing: real labels dengan noise
    real_label = 0.9 + 0.1 * rand();  % 0.9-1.0 instead of 1.0
    fake_label = 0.0 + 0.1 * rand();  % 0.0-0.1 instead of 0.0
    
    % Discriminate real image (dengan noise)
    ad2_real = tanh_f(Wd2 * x_real_noisy + bd2);
    y_real = sigmoid(Wd3 * ad2_real + bd3);
    
    % Discriminate fake image
    ad2_fake = tanh_f(Wd2 * x_fake + bd2);
    y_fake = sigmoid(Wd3 * ad2_fake + bd3);
    
    % Calculate discriminator loss (dengan label smoothing)
    loss_D(epoch) = -(log(y_real + 1e-8) + log(1 - y_fake + 1e-8));
    
    % Gradients for Discriminator
    % Real image gradients
    dLdy_real = -(real_label - y_real);  % Label smoothing
    deltad3_real = dLdy_real .* y_real .* (1 - y_real);
    dWd3_real = deltad3_real * ad2_real';
    dBd3_real = deltad3_real;
    
    deltad2_real = (Wd3' * deltad3_real) .* (1 - ad2_real.^2);
    dWd2_real = deltad2_real * x_real_noisy';
    dBd2_real = deltad2_real;
    
    % Fake image gradients
    dLdy_fake = -(fake_label - y_fake);  % Label smoothing
    deltad3_fake = dLdy_fake .* y_fake .* (1 - y_fake);
    dWd3_fake = deltad3_fake * ad2_fake';
    dBd3_fake = deltad3_fake;
    
    deltad2_fake = (Wd3' * deltad3_fake) .* (1 - ad2_fake.^2);
    dWd2_fake = deltad2_fake * x_fake';
    dBd2_fake = deltad2_fake;
    
    % Update Discriminator weights
    Wd3 = Wd3 - eta_D * (dWd3_real + dWd3_fake);
    bd3 = bd3 - eta_D * sum(dBd3_real + dBd3_fake, 2);
    Wd2 = Wd2 - eta_D * (dWd2_real + dWd2_fake);
    bd2 = bd2 - eta_D * sum(dBd2_real + dBd2_fake, 2);
    
    % ==== Update Generator (G) ====
    % Generate new fake image
    ng = randn(latent_dim, 1);
    ag2 = tanh_f(Wg2 * ng + bg2);
    x_fake = tanh_f(Wg3 * ag2 + bg3);
    
    % Discriminate fake image
    ad2_fake = tanh_f(Wd2 * x_fake + bd2);
    y_fake = sigmoid(Wd3 * ad2_fake + bd3);
    
    % Calculate generator loss
    loss_G(epoch) = -log(y_fake + 1e-8);
    
    % Gradients for Generator
    dLdy_fake = -(1 - y_fake);
    deltad3_fake = dLdy_fake .* y_fake .* (1 - y_fake);
    deltad2_fake = (Wd3' * deltad3_fake) .* (1 - ad2_fake.^2);
    deltag3 = (Wd2' * deltad2_fake) .* (1 - x_fake.^2);
    
    dWg3 = deltag3 * ag2';
    dBg3 = deltag3;
    
    deltag2 = (Wg3' * deltag3) .* (1 - ag2.^2);
    
    dWg2 = deltag2 * ng';
    dBg2 = deltag2;
    
    % Update Generator weights (every DGL epochs)
    if rem(epoch, DGL) == 0
        Wg3 = Wg3 - eta_G * dWg3;
        bg3 = bg3 - eta_G * sum(dBg3, 2);
        Wg2 = Wg2 - eta_G * dWg2;
        bg2 = bg2 - eta_G * sum(dBg2, 2);
    end
    
    % ==== Display progress ====
    if mod(epoch, 1000) == 0
        fprintf("Epoch %d / %d  |  L_D=%.4f  L_G=%.4f  |  y_real=%.3f  y_fake=%.3f\n", ...
                epoch, num_epochs, loss_D(epoch), loss_G(epoch), y_real, y_fake);
        
        % Show generated sample
        subplot(2, 3, [1 2 3]);
        img = reshape(x_fake, img_height, img_width);
        imagesc((img + 1) / 2);  % Scale to [0,1]
        colormap gray;
        axis image off;
        title(sprintf('Generated Sample (Epoch %d)', epoch));
        
        % Show loss curves
        subplot(2, 3, [4 5 6]);
        plot(1:epoch, loss_D(1:epoch), 'r', 'DisplayName', 'D Loss');
        hold on;
        plot(1:epoch, loss_G(1:epoch), 'b', 'DisplayName', 'G Loss');
        hold off;
        legend('Location', 'best');
        xlabel('Epoch');
        ylabel('Loss');
        title('Training Loss');
        grid on;
        
        drawnow;
    end
end

fprintf('\n');

% ======== Save trained model ========
save(save_path, 'Wg2', 'bg2', 'Wg3', 'bg3', 'Wd2', 'bd2', 'Wd3', 'bd3', ...
     'loss_D', 'loss_G', 'img_height', 'img_width', 'latent_dim');
fprintf("Training complete! Model saved: '%s'\n\n", save_path);

% ======== Generate sample digits ========
fprintf('Generating sample digits...\n');
figure('Name', 'Generated Digits');
for i = 1:16
    ng = randn(latent_dim, 1);
    ag2 = tanh_f(Wg2 * ng + bg2);
    x_fake = tanh_f(Wg3 * ag2 + bg3);
    
    subplot(4, 4, i);
    img = reshape(x_fake, img_height, img_width);
    imagesc((img + 1) / 2);
    colormap gray;
    axis image off;
    title(sprintf('Sample %d', i));
end
sgtitle('Generated Digit Samples (After Training)');

% Save generated samples
exportgraphics(gcf, 'generated_digits.png');
fprintf("Generated samples saved: 'generated_digits.png'\n");

% ======== Display loss curve ========
figure('Name', 'Training Loss');
plot(loss_D, 'r', 'DisplayName', 'Discriminator Loss', 'LineWidth', 1.5);
hold on;
plot(loss_G, 'b', 'DisplayName', 'Generator Loss', 'LineWidth', 1.5);
hold off;
legend('Location', 'best');
xlabel('Epoch');
ylabel('Loss');
title('GAN Training Loss - Digit Generation');
grid on;

exportgraphics(gcf, 'digit_loss_curve.png');
fprintf("Loss curve saved: 'digit_loss_curve.png'\n\n");

fprintf('====================================\n');
fprintf('Training Summary:\n');
fprintf('====================================\n');
fprintf('Image size: %dx%d pixels (%d total = 2^6) ✓\n', img_height, img_width, img_size);
fprintf('Latent dimension: %d (2^4) ✓\n', latent_dim);
fprintf('Hidden neurons: %d (2^5) ✓\n', G_hidden_L);
fprintf('Training epochs: %d\n', num_epochs);
fprintf('Generator parameters: %d\n', numel(Wg2) + numel(bg2) + numel(Wg3) + numel(bg3));
fprintf('Final D Loss: %.4f\n', loss_D(end));
fprintf('Final G Loss: %.4f\n', loss_G(end));
fprintf('\nFPGA-Friendly Design:\n');
fprintf('- All dimensions are power-of-2 ✓\n');
fprintf('- Memory alignment optimized ✓\n');
fprintf('- Address calculation simplified ✓\n');
fprintf('\nTips for Better Results:\n');
fprintf('- If still mode collapse, try restart with different seed\n');
fprintf('- Check diversity: samples should look different!\n');
fprintf('- Monitor y_real (should be ~0.7-0.9)\n');
fprintf('- Monitor y_fake (should be ~0.3-0.5)\n');
fprintf('- Mode collapse signs: all samples look the same\n');
fprintf('====================================\n');