GOTM_DNN
================

## 1. Introduction

This repository contains the modified codes of the General Ocean
Turbulence Model (**GOTM**) reported in Yuan et al. (2024) "The K-profile Parameterization augmented by Deep Neural Networks (KPP_DNN) in the General Ocean Turbulence Model (GOTM)". 
The manuscript is currently under review at the Journal of Advances in Modeling Earth System. The
modifications incorporate trained deep neural networks (**DNNs**) to
predict two critical parameters in the K-profile parameterization
scheme: the velocity scale coefficient ($\epsilon$) and the unresolved
shear coefficient ($\eta$).

If you are interested in the LES solutions to train the DNN model, please feel free to email us (jliang at lsu.edu).

DNNs are typically trained using Python or other advanced programming
languages, whereas GOTM and many other ocean models are developed in the
basic Fortran language. To integrate DNNs into GOTM both flexibly and
efficiently, the Fortran-Keras Bridge module (FKB, Ott (2020)) has been
implemented. Detailed information about FKB, including download
instructions and operational details, can be found at
<https://github.com/scientific-computing/FKB>.

In the GOTM module `kpp`, the system reads a pre-processed text file
containing DNN structure and weight information to reconstruct the
model. Subsequently, the model digests necessary input values from GOTM,
including temperature and salinity profiles (plus Stokes profiles,
depending on the model setup), various forcing conditions, and the
height of the surface boundary layer from the previous timestep, to make
predictions.

Additionally, the modification integrates the COARE bulk air-sea flux
algorithm version 3.6 (COARE-v3.6) into GOTM’s airsea.F. This
enhancement enables GOTM to calculate latent heat, sensible heat,
outgoing longwave radiation, and evaporation rates online during
runtime.

## 2. Download, installation and compile

At first, download the gotm_dnn folder from github.

``` bash
git clone https://github.com/lsuocean/KPP_DNN_in_GOTM`
```

This directory is built on the `gotmwork` folder by Dr. Qing Li, with
modifications to ensure installations use our modified GOTM-DNN
model.Details on how to install and compile the GOTM-DNN model is
provided in setup_gotmwork.sh file, as well as on Dr. Qing Li’s github
gotmwork readme webpage (<https://github.com/qingli411/gotmwork>).

## 3. Configuring DNN Options in GOTM-DNN

The DNNs are incorporated into the GOTM module `kpp` and wrapped around
**CVMix** package and can be activated by modifying the following
entries in `kpp.nml` under the subdirectory `namelist`:

- `langmuir_method`:
  - `5`, to use DNNs to predict $\epsilon$ only.
  - `6`, to use DNNs to predict both $\eta$ and $\epsilon$
- `dnn_f1`: structure and weights information for the DNN predicting
  $\epsilon$
- `dnn_f2`: structure and weights information for the DNN predicting
  $\eta$
- `inp_f_mean`: the array of mean value to normalize DNN inputs
- `inp_f_sd`: the array of standard deviation value to normalize DNN
  inputs
- `Efac_f_param`: the array of parameters to de-normalize $\epsilon$
- `Vtfac_f_param`: the array of parameters to de-normalize $\eta$
- `dnn_stokes`:
- `.true.` when DNN inputs include stokes drift profile,
- `.false.` when DNN inputs do not include stokes drift profile

**Note**:

The default option for `dnn_stokes` is `.true.`. Switching it to
`.false.` reduces the size of the DNN input array. The input array size
is not managed in the `kpp.nml` file, thus users need to manually adjust
the size of `dnn_input` in GOTM source code file `kpp.F90` accordingly,
then re-compile the GOTM model before running it.

## 4. Enabling the COARE Algorithm in GOTM-DNN

The COARE-v3.6 algorithm is incorporated into the GOTM model `airsea`
and can be activated by modifying the following entries in `airsea.nml`
under the subdirectory `namelist`:

- `calc_fluxes`: should be set to `.true.` to activate bulk formulae
- `fluxes_method`: option `3` for COARE-v3.6
