# -*- coding: utf-8 -*-
"""
spatial_accuracy_csv_editor.py
@author: Rain Younger
Created on Tue May  6 14:26:19 2025

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

This code is meant to extract mouse ID, file dates, sessions, phases, and cue 
status and add new columns to the excel sheet with these variables

------------------------------------------------------------------------------

Files needed in the working directory:
    spat_acc_funct.py
    The csv file to be edited
    spatial_accuracy_csv_editor.py
"""

import pandas as pd

# with open('place_accuracy.csv', newline = '') as csvfile:
#     datalist = list(csv.reader(csvfile))

# data = np.asarray(datalist)
def spatial_accuracy_csv_editor(directory, filename):
    """
    Extract mouse ID, session number, phase number, cue status, and date as
    new columns, save the edited dataframe as a new excel sheet, and return
    the edited dataframe.

    Parameters
    ----------
    directory: str with path to the csv file
    
    filename : str with the name of the csv file to be run. Organization of the
        file assumes it was run through the 'TargetTrajectories_JB2_Feb2021_
        endtests_Mice_Goal_Dylantemp4' MATLAB code. The csv file will be read 
        in a RxC format where R = number of rows and C = number of columns. 
        The first column, should contain the full names of the files the data
        from each row was collected from in the following format:
        mWsXpYZ_mmddyy where W = mouse id, X = session #, Y = phase #, Z =
        cued or uncued status, and the date in month/day/year format is 
        written after the underscore.
        

    Returns
    -------
    data : A pandas dataframe which contains the data from filename with 
    extracted mouse ID, session number, phase number, cue status, and date as
    new columns.

    """    

    
    # Load the dataframe from the spatial accuracy csv
    data = pd.read_csv(filename, index_col=False)
    
    # count_row = df.shape[0]  # Gives number of rows
    # count_col = df.shape[1]  # Gives number of columns
    
    data.columns.values[0] = 'file'
    # In case some people have added uppercase characters, this converts to lower case
    data['file'] = data['file'].str.lower()
    
    # Create a column for the mouse ID number
    data.insert(1,'mouse_id',0)
    
    # For loop which will extract the mouse ID from the file name and put it
    # into the new mouse_id column. There is probably a more efficient way to
    # do this and putting the extract ID into mouse_id, but ¯\_(ツ)_/¯
    for row_index, row in data.iterrows():
        file_name = row['file']# Take the file name as a string
        # The file name should have the format as described above, but the if
        # statements keep the program running if that is not the case
        if 'm' in file_name:
            file_mouse = file_name.index('m')# Find the index for 'm'
            if 's' in file_name:
                file_session = file_name.index('s')# Find the index for 's'
                # Using the m and s indices, take the mouse ID from file_name and 
                # convert it to an int
                mouse_id = int(file_name[(file_mouse + 1):file_session])
                # Add the ID number to mouse_id
                data.at[row_index, 'mouse_id'] = mouse_id 
            else: continue
        else: continue
        
    # Rinse and repeat the mouse ID extraction for session, phase, cue, and
    # date
    
    # Create a column for session number
    data.insert(2,'session',0)
    
    # For loop which will extract the mouse session number from the file name 
    # and put it into the new session column
    for row_index, row in data.iterrows():
        file_name = row['file']# Take the file name as a string
        # The file name should have the format as described above, but the if
        # statements keep the program running if that is not the case
        if 's' in file_name:
            file_session = file_name.index('s')# Find the index for 's'
            if 'p' in file_name:
                file_phase = file_name.index('p')# Find the index for 'p'
                # Using the s and p indices, take the session from file_name  
                # and convert it to an int
                session_number = int(file_name[(file_session + 1):file_phase])
                # Add the session number to session
                data.at[row_index, 'session'] = session_number 
            else: continue
        else: continue
        
        
    
    # Create a column for phase number
    data.insert(3,'phase',0)
    
    # For loop which will extract the mouse phase number from the file name 
    # and put it into the new session column
    for row_index, row in data.iterrows():
        file_name = row['file']# Take the file name as a string
        # The file name should have the format as described above, but the if
        # statements keep the program running if that is not the case
        if 'p' in file_name:
            file_phase = file_name.index('p')# Find the index for 'p'
            if 'c' in file_name:
                file_cue = file_name.index('c')# Find the index for cue
                # Using the p and c indices, take the phase from file_name and 
                # convert it to an int
                phase_number = int(file_name[(file_phase + 1):file_cue])
                # Add the phase number to phase
                data.at[row_index, 'phase'] = phase_number 
            elif 'u' in file_name:
                file_cue = file_name.index('u')# Find the index for cue
                # Using the p and u indices, take the phase from file_name and 
                # convert it to an int
                phase_number = int(file_name[(file_phase + 1):file_cue])
                # Add the phase number to phase
                data.at[row_index, 'phase'] = phase_number 
            else: continue
        else: continue
       
    # Create a column for cued/uncued
    data.insert(4,'cue','x')
    
    # For loop which will extract the mouse session number from the file name 
    # and put it into the new session column
    for row_index, row in data.iterrows():
        file_name = row['file']# Take the file name as a string
        # The file name should have the format as described above, but the if
        # statements keep the program running if that is not the case
        if 'c' in file_name:
            file_cue = file_name.index('c')# Find the index for 'c'
            # Using the c index, take the cue from file_name
            cue = 'cued'
            # Add the cue number to cue
            data.at[row_index, 'cue'] = cue 
        elif 'u' in file_name:
            file_cue = file_name.index('u')# Find the index for 'u'
            # Using the u index, take the cue from file_name
            cue = 'uncued'
            # Add the cue number to cue
            data.at[row_index, 'cue'] = cue 
        else: continue
    
    # Create a column for date in the mmddyy format. I could change thise to
    # something else, but that sounds like a lot of work with little benefit
    # Sorry future coding friend (maybe me) who wishes I did this on 050725
    data.insert(5,'date', '0')
    
    # For loop which will extract the mouse session number from the file name 
    # and put it into the new session column
    for row_index, row in data.iterrows():
        file_name = row['file']# Take the file name as a string
        # The file name should have the format as described above, but the if
        # statements keep the program running if that is not the case
        if '_' in file_name:
            file_predate = file_name.index('_')# Find the index for '_'
            # Using the _ index, take the date from file_name
            # The date is kept as a str in the hopes it will keep the 0 at the
            # beginning of the mmddyy format
            date = (file_name[(file_predate + 1):(file_predate + 7)])
            # Add the cue number to cue
            data.at[row_index, 'date'] = date 
        elif 'c' in file_name:
            file_predate = file_name.index('c')# Find the index for 'c'
            # Using the c index, take the date from file_name
            # The date is kept as a str in the hopes it will keep the 0 at the
            # beginning of the mmddyy format
            date = (file_name[(file_predate + 1):(file_predate + 7)])
            # Add the cue number to cue
            data.at[row_index, 'date'] = date
        elif 'u' in file_name:
            file_predate = file_name.index('u')# Find the index for 'u'
            # Using the u index, take the date from file_name
            # The date is kept as a str in the hopes it will keep the 0 at the
            # beginning of the mmddyy format
            date = (file_name[(file_predate + 1):(file_predate + 7)])
            # Add the cue number to cue
            data.at[row_index, 'date'] = date 
        else: continue
    
    # Sort the dataframe in a way which will have sessions ascending by 
    # individual mouse ID
    data = data.sort_values(by=['mouse_id', 'session'])
    
    # Save the dataframe with extracted variables as a new excel sheet
    with pd.ExcelWriter(f'{directory}\\spatial_accuracy_edited.xlsx') as writer:
        data.to_excel(writer, index=False)  
    return data
    









    
    
    
    
    
    
    
    