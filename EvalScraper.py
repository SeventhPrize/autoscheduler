'''
George Lyu 11/21/2021
Scrapes for Esther course evaluation data for each course in input .csv file.
Write data and course evaluation metrics to a .csv file.
'''
import requests
import csv
import time
import random
from bs4 import BeautifulSoup

print("___START___")

def evalUrl(term, crn):
    '''
    Constructs a url to access the Esther course evaluations of a given course
    IN
        term; term fo the course
        crn; crn number of the course
    OUT
        string url of the eval page
    '''
    return "https://esther.rice.edu/selfserve/swkscmt.main?p_term=" + str(term) + "&p_crn=" + str(crn) + "&p_commentid=&p_confirm=1&p_type=Course"

def readCsvCourselist(filename):
    '''
    Reads a csv file containing data for each unique course, including term and crn numbers
    IN
        filename, string .csv filename of the csv file
    OUT
        data; list of course data, where each element is a list containing data for that course
        labels; list of string names of variables in data
    '''
    data = []
    with open(filename, encoding='utf-8-sig') as csvfile:
        reader = csv.reader(csvfile)
        counter = 0
        for row in reader:
            counter += 1
            if counter == 1:
                labels = row
            else:
                data.append(row)
    return data, labels


def scrapeEval(url, authCookie):
    '''
    Retrieves the course evaluation survey numerical metrics from the given url
    IN
        url; string url accessing the webpage containing esther course evals
        authCookie; SESSID cookie used to authenticate access
    OUT
        list of numerical metrics shown by the charts in eval webpage
    '''
    metrics = [None] * 8

    time.sleep(random.randint(1,4) / 2) # prevent aggressive scraping
    req = requests.get(url, cookies=authCookie)
    soup = BeautifulSoup(req.content, 'html.parser')

    charts = soup.find_all('div', class_="chart")

    # from each numerical chart, collect the "class average" metric
    for ind in range(len(charts)):
        chart = charts[ind]
        filler = chart.find('div', class_='filler')
        third = filler.find('div', class_='third')
        dataStr = third.get_text()
        colonInd = dataStr.find(":")
        data = float(dataStr[colonInd + 1:].strip())
        metrics[ind] = data
    
    # if no metrics were found, report that no metrics were collected
    if metrics[7] == None:
        print("Evaluatations data not found for url " + url)

    return metrics

def writeCsv(fieldHeaders, courseData, filename):
    '''
    Writes course data to a csv file
    IN 
        fieldHeaders; list of strings representing the column headers in csv
        courseData; data to record in csv
        filename; string name (end in ".csv") of file to write to
    '''
    with open(filename, 'w', newline='', encoding='utf-8-sig') as csvfile:
        csvwriter = csv.writer(csvfile) 
        csvwriter.writerow(fieldHeaders) 
        csvwriter.writerows(courseData)


# SESSID used to authenticate Esther Eval session
authCookie = {"SESSID" : "<COOKIE HERE>"}

# Import csv data containing information for each unique course
data, labels = readCsvCourselist("Caam378 MP3 - Course Data 2020 - 2021.csv")
#print(data)
print(labels)

# Find indices of the term and crn of each course, used to generate the url of the eval page
termInd = labels.index("Recent Term")
crnInd = labels.index("CRN")

metricLabels = ["organization", "assignments", "quality", "challenge", "workload", "credit", "grade", "pass"]
labels.extend(metricLabels)

# Foreach of the 1000 highest-enrollment courses in the csv file,
# repeatedly try to scrape data until successful (protects againt network failure)
for ind in range(1000):
    url = evalUrl(data[ind][termInd], data[ind][crnInd])
    print(ind)
    print(url)
    success = False
    failcount = 0
    while not success:
        try:
            metrics = scrapeEval(url, authCookie)
            success = True
            print(metrics)
        except:
            pass
        data[ind].extend(metrics)

# Write data to new csv file
csvFilename = "2021 Course Eval Information 1000.csv"
writeCsv(labels, data, csvFilename)

print("_____END_____")

