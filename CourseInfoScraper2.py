'''
George Lyu 11/21/2021
Scrapes data for each course in a given .csv file. Assumes there are no duplicate courses in the .csv file for faster scraping.
Compiles data related to items in given keyFields.
'''
import requests
import csv
import time
import random
from bs4 import BeautifulSoup

print("___START___")

# Collects data related to the fields listed. 
DEFUALT_KEYFIELDS = ['long title', 'distribution group', 'credit hours', 'prerequisites', 'corequisites', 'section max enrollment', 'section enrolled']

def readCsvCourselist(filename):
    '''
    Reads a csv file containing information for each full-term course offered in 2020-21 academic year.
    IN
        filename; string .csv file contianing data for each course
    OUT
        data; list, where each element is a list of course data
        labels; list, where each element is a variable title for each column in the csv file
    '''
    data = []
    with open(filename, encoding='utf-8') as csvfile:
        reader = csv.reader(csvfile)
        counter = 0
        for row in reader:
            counter += 1
            # record column headers
            if counter == 1:
                labels = row
            else:
                data.append(row)
    return data, labels


def scrapeCourse(url, keyFields=DEFUALT_KEYFIELDS):
    '''
    Scrapes a course's webpage for all course fields in keyFields
    IN
        url; string url of the course's webpage
        keyFields; list of LOWERCASE strings representing the field values to collect
    OUT
        subInfo; list of values under and in the same order as specified by keyFields
    '''
    print(url)
    time.sleep(random.randint(1,2)) # prevent aggressive web scraping 
    req = requests.get(url)
    soup = BeautifulSoup(req.content, 'html.parser')

    subInfo = [None] * len(keyFields)

    # Get fields in keyFields
    allInfo = soup.find_all('div', class_='col-lg-6')
    for iter in range(2):
        info = allInfo[iter]
        for div in info:
            # determine which field this value fallls under
            info = div.get_text()
            colonInd = info.find(":")
            if colonInd > 0:
                field = info[:colonInd].strip().lower()
                # if the field is in keyFields, add to the subInfo list
                if field in keyFields:
                    value = info[colonInd + 1:].strip()
                    subInfo[keyFields.index(field)] = value

    return subInfo


def writeCsv(fieldHeaders, courseData, filename):
    '''
    Writes course data to a csv file
    IN 
        fieldHeaders; list of strings representing the column headers in csv
        courseData; data to record in csv
        filename; string name (end in ".csv") of file to write to
    '''
    with open(filename, 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile) 
        csvwriter.writerow(fieldHeaders) 
        csvwriter.writerows(courseData)

# Read csv that contains data for each unique course in 2020-2021 academic year
data, labels = readCsvCourselist('Caam378 MP3 - 2020-2021 Course List Summary.csv')
labels[0] = "Title" # fix import issue

keyFields = DEFUALT_KEYFIELDS
subInfo = [None] * len(data)
urlInd = labels.index("URL")
labels.extend(keyFields)

# Foreach unique course in the csv file, repeatedly try to scrape data until successful (protects againt network failure)
for ind in range(len(data)):
    success = False
    print(ind / len(data)) # report progress
    while not success:
        try:
            subdata = scrapeCourse(data[ind][urlInd])
            success = True
        except:
            pass
    
    data[ind].extend(subdata)


# Record scraped data to new csv file
print(labels)
print(data)

csvFilename = "2021 Course Information.csv"
writeCsv(labels, data, csvFilename)



print("_____END_____")


