# EEG GAN Implementation 沖縄IKZ

We are team GANteng from Institut Teknologi Bandung, from the School of Electical Engineering and Informatics. This repository is our implementation, test, and evaluation used for 2026 LSI Design Competition hosted in Okinawa, University of the Ryukyus Faculty of Engineering, where for the 2026 competition, the challenge is "Generative Adversarial Networks(GAN)". 

For the LSI competition, we decided to tackle EEG artifacts denoising and design and architecture for hardware. The finishing document and report can be found in the `docs` directory.


## Content

```bash
.
|-- data
|   `-- eeg_denoise_net
|-- docs
|   `-- overleaf_code
|-- output
|   |-- decoder
|   |   `-- seeds
|   `-- out
|-- src
|   |-- AXON
|   |-- System_Integration
|   |-- Transpose_Convolution
|   |-- models
|   |   |-- G_d5_Q9.14
|   |   `-- main3_d5_b
|   `-- notebooks
|       |-- attempt_nb
|       |-- main_3
|       |-- manual_implementation
|       `-- test_notebook
`-- test
    |-- input_sample_Q9.14
    |-- input_sample_Q9.14_10
    `-- out_input
```

This repository consists of software notebooks to create the base models, and verilog source code for design and test bench. More specifically, the detail for each directory is as follows:

### Base Directory
1. `data` contains raw training data that is provided by [EEGdenoiseNet](github.com/ncclabsustech/EEGdenoiseNet).
2. `docs` contains latex raw source code and our final document for submission
3. `test` contains test input used for testing our model in software and hardware
4. `output` contains outputs from `test` using both software and hardware design
5. `src`contains raw source code for notebooks and verilog implementation

### `src` Directory
1. `src/models` contains our final trained models to be imported and tested with. The models were not commited to not flood the github repository, however can be produced back, using the `final_model.ipynb`
2. `src/notebooks` contains our `.ipynb` notebooks used to train our models, generate input/output, and also test comparison of hardware and software outputs.
3. `src/AXON`
4. `src/System_Integration`
5. `src/Transpose_Convolution`

## Setup

To execute python notebooks, be sure to setup environment and download the necessary libraries. 

1. Create venv
```bash
python -m venv venv
```

2. Activate venv
```bash
source venv/Scripts/activate # or however to activate venv in your system
```

3. Install requirements
```bash
pip install -r requirements.txt
```

After running the commands above, you should be able to run the notebooks. However you could just see directly the contents of the notebooks to see the outputs of each cell.