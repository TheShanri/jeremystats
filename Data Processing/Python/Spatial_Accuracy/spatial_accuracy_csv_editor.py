# -*- coding: utf-8 -*-
"""
spatial_accuracy_csv_editor.py
@author: Rain Younger
Created on Wed May  7 10:43:45 2025

⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣤⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣠⣾⣿⣿⣶⣄⠀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡆⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⣾⣿⣿⣿⣿⣿⣿⣷⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⣀⣀⡀⠀⠀⠀
⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦⡀⠀
⠀⢠⣶⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⠀
⠀⢾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇⠀
⠀⠈⠿⣿⣿⡿⠋⠈⠻⣿⣿⣿⣿⡿⠟⠁⠀⠙⠿⠿⠛⠁⠙⠻⠿⠿⠟⠁⠀⠀
⠀⠀⠀⠀⣠⡀⠀⠀⢦⡄⠉⠉⣁⠀⠀⠀⠀⠀⠀⠰⡆⠀⠀⢰⣆⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠸⠇⠀⠀⠈⠀⠀⠀⠛⠀⠀⠀⢹⡇⠀⠀⠀⠀⠀⠀⠛⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⡀⠀⠀⢰⡄⠀⠀⣀⠀⠀⠈⠛⠀⠀⢰⣧⠀⠀⠀⣀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠸⣷⠀⠀⠈⠉⠀⠀⢻⡇⠀⠀⠀⡀⠀⠀⠉⠀⠀⠀⢻⡄⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠛⠂⠀⠀⢠⡄⠀⠈⠟⠀⠀⠀⢿⠀⠀⠀⣤⠀⠀⠈⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣠⡀⠀⠀⠃⠀⠀⠀⣀⠀⠀⠘⠃⠀⠀⠉⠀⠀⠀⢰⡄⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠘⠃⠀⠀⠀⠀⠀⠀⠛⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⠓⠀⠀

------------------------------------------------------------------------------

Workspace to utilize the spat_acc_funct.py module. Following the script below
will edit the input csv file and output an excel sheet with new columns 
containing the mouse ID, session number, phase number, cue status, and date.

------------------------------------------------------------------------------

Files needed in the working directory:
    spat_acc_funct.py
    The csv file to be edited
    spatial_accuracy_csv_editor.py
"""

import spat_acc_funct as spat
import os

# Change this to the working directory with all the files listed above
os.chdir('C:\\Users\\example\\Spatial_Accuracy')
# Store the current working directory into the "directory" variable
directory = os.getcwd()
# Run the function to extract the variables as new columns
x = spat.spatial_accuracy_csv_editor(directory, 'place_accuracy.csv')