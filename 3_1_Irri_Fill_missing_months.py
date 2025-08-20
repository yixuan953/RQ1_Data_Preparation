import xarray as xr
import numpy as np
import os
import pandas as pd

# === Paths ===
process_dir = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"
all_crops = ["winterwheat", "maize", "mainrice", "soybean", "secondrice"]
complete_times = pd.date_range('1981-01-01', '2016-12-01', freq='MS')

for crop in all_crops:

    file_path = os.path.join(process_dir, f"temp_renamed_{crop}.nc")
    ds = xr.open_dataset(file_path)

    times = pd.DatetimeIndex(ds["time"].values)
    first_day_times = pd.DatetimeIndex([pd.Timestamp(year=t.year, month=t.month, day=1, hour=0, minute=0, second=0) 
                                    for t in times])
    ds = ds.assign_coords({"time": first_day_times})
    template = ds.isel({"time": 0})
    filled_data_vars = {}

    for var_name, var in ds.data_vars.items():
        # If the variable has a time dimension
        if "time" in var.dims:
            # Create a new array for this variable with the complete time series
            shape = list(var.shape)
            time_dim_idx = var.dims.index("time")
            shape[time_dim_idx] = len(complete_times)
            
            # Initialize with zeros (missing months will remain as zeros)
            filled_data = np.zeros(shape, dtype=var.dtype)
            
            # Get the indices to map from old times to new times
            time_indices = np.where(np.isin(complete_times, first_day_times))[0]
            
            # Create slices for each dimension
            slices = [slice(None)] * len(var.dims)
            
            # Fill the data for existing months
            for i, idx in enumerate(time_indices):
                slices[time_dim_idx] = idx
                filled_data[tuple(slices)] = var.isel({"time": i}).values
            
            # Create new DataArray with the filled data
            filled_data_vars[var_name] = xr.DataArray(
                data=filled_data,
                dims=var.dims,
                coords={dim: (complete_times if dim == "time" else ds[dim]) for dim in var.dims},
                attrs=var.attrs
            )
        else:
            # If variable doesn't have time dimension, just copy it
            filled_data_vars[var_name] = var

    # Create the new dataset
    complete_ds = xr.Dataset(
        data_vars=filled_data_vars,
        coords={coord_name: (complete_times if coord_name == "time" else coord) 
                for coord_name, coord in ds.coords.items()},
        attrs=ds.attrs
    )

    # Save the modified dataset to a new file
    output_path = os.path.join(process_dir, f"temp_aligned_{crop}.nc")
    complete_ds.to_netcdf(output_path)
    print(f"File with missing months filled saved to: {output_path}")