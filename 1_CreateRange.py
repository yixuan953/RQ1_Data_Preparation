from osgeo import gdal, ogr
import numpy as np
import xarray as xr
import os

input_dir = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_shp_StudyArea"
output_dir = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"
StudyAreas = ['LaPlata', 'Indus', 'Yangtze', 'Rhine']
res = 0.5  # degree resolution

# Align edges to .25/.75 pixel centers
def align_edges(xmin, xmax, ymin, ymax, res):
    xmin_aligned = np.floor(xmin * 2) / 2 + 0.25
    xmax_aligned = np.ceil(xmax * 2) / 2 - 0.25
    ymin_aligned = np.floor(ymin * 2) / 2 + 0.25
    ymax_aligned = np.ceil(ymax * 2) / 2 - 0.25
    return xmin_aligned, xmax_aligned, ymin_aligned, ymax_aligned

for studyarea in StudyAreas:
    shp_file = os.path.join(input_dir, studyarea, f"{studyarea}.shp")
    out_nc = os.path.join(output_dir, studyarea, "range.nc")
    os.makedirs(os.path.dirname(out_nc), exist_ok=True)

    # Read shapefile
    shp = ogr.Open(shp_file)
    layer = shp.GetLayer()

    # Original extent
    xmin, xmax, ymin, ymax = layer.GetExtent()

    # Expand bounding box by half pixel in each direction
    xmin -= res / 2
    xmax += res / 2
    ymin -= res / 2
    ymax += res / 2

    # Align edges to .25/.75 centers
    xmin, xmax, ymin, ymax = align_edges(xmin, xmax, ymin, ymax, res)

    # Compute coordinate arrays
    lon = np.arange(xmin, xmax + 0.001, res)
    lat = np.arange(ymax, ymin - 0.001, -res)
    width, height = len(lon), len(lat)

    # Create in-memory raster
    target_ds = gdal.GetDriverByName('MEM').Create('', width, height, 1, gdal.GDT_Byte)
    transform = (xmin - res / 2, res, 0, ymax + res / 2, 0, -res)
    target_ds.SetGeoTransform(transform)
    target_ds.SetProjection(layer.GetSpatialRef().ExportToWkt())

    band = target_ds.GetRasterBand(1)
    band.Fill(0)

    # Rasterize with ALL_TOUCHED
    gdal.RasterizeLayer(
        target_ds,
        [1],
        layer,
        burn_values=[1],
        options=["ALL_TOUCHED=TRUE"]
    )

    # Read mask array
    arr = band.ReadAsArray()

    # Save to NetCDF
    da = xr.DataArray(arr, coords=[('lat', lat), ('lon', lon)], name='mask')
    da.to_netcdf(out_nc)

    print(f"{studyarea} -> {out_nc}")



