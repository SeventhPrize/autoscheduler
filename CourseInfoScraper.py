'''
George Lyu 11/21/2021
This code is unused. This attempts to scrape information for all courses, even duplicate courses, which leads to very long runtimes.
See CourseInfoScraper2 for a better implementation; imports a csv of unique courses so no duplicate courses are scraped (5x less scraping).
'''
import requests
import csv
import time
import random
from bs4 import BeautifulSoup


print("___START___")

DEFUALT_KEYFIELDS = ['long title', 'distribution group', 'credit hours', 'prerequisites', 'corequisites', 'section max enrollment', 'section enrolled']

def courseUrl(term, crn):
    '''
    Constructs a url to access a course's data
    IN
        term; term of the course
        crn; crn number of the course
    OUT
        string url of the course data
    '''
    return "https://courses/courses/!SWKSCAT.cat?p_action=COURSE&p_term=" + str(term) + "&p_crn=" + str(crn)

def catalogueUrl(term):
    '''
    Constructs a url to access the course catalogue containing all FULL TERM courses of a term
    IN
        term; term of the course catalogue
    OUT
        string url of the catalogue's page 
    '''
    return "https://courses.rice.edu/courses/courses/!SWKSCAT.cat?p_action=QUERY&p_term=" + str(term) + "&p_ptrm=1&p_crn=&p_onebar=&p_mode=AND&p_subj_cd=&p_subj=&p_dept=&p_school=&p_spon_coll=&p_df=&p_insm=&p_submit="
    

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

def scrapeCatalogue(term):
    '''
    Scrapes a term's course catalogue to obtain all course urls from the catalogue
    IN
        term; term of the course catalogue
    OUT
        list of url strings; each url accesses one course from the term
    '''
    req = requests.get(catalogueUrl(term))
    soup = BeautifulSoup(req.content, 'html.parser')
    urls = []

    # Iterate through each url and append to list
    for td in soup.find_all('td', class_='cls-crn'):
        for a in td.find_all('a'):
            urls.append("https://courses.rice.edu" + a['href'])
    return urls




def scrapeCourse(url, keyFields=DEFUALT_KEYFIELDS):
    '''
    Scrapes a course's webpage for all course fields in keyFields
    IN
        url; string url of the course's webpage
        keyFields; list of LOWERCASE strings representing the field values to collect
    OUT
        mainInfo; list of [0] = title; [1] = crn; [2] = term
        subInfo; list of values under and in the same order as specified by keyFields
    '''
    print(url)
    time.sleep(random.randint(1,3)) # prevent aggressive web scraping 
    req = requests.get(url)
    soup = BeautifulSoup(req.content, 'html.parser')

    mainInfo = [None] * 3 # [0] = title; [1] = crn; [2] = term
    subInfo = [None] * len(keyFields)

    # Get title and crn from page title
    titleDiv = soup.find_all('div', class_="col-lg-12")[3]
    titleStr = titleDiv.contents[0].get_text()
    title = titleStr[:8]
    mainInfo[0] = title
    crn = titleStr[-6:-1]
    mainInfo[1] = crn

    # Get term from url
    termInd = url.find("p_term=")
    term = url[termInd + 7 : termInd + 13].strip()
    mainInfo[2] = term

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

    return mainInfo, subInfo


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

    time.sleep(random.randint(1,3)) # prevent aggressive scraping
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

def scrapeCourseDetails(url, authCookie, keyFields=DEFUALT_KEYFIELDS):
    '''
    Scrapes for all information of the specified course, collecting both logistical information and evals data
    IN
        url; url of the course's webpage
        authCookie; SESSID cookie used to authentical esther evals access
        keyFields; names of the course webpage fields to collect
    OUT
        list of course information
    '''
    mainInfo, subInfo = scrapeCourse(url, keyFields) # get course logistics information
    metrics = scrapeEval(evalUrl(mainInfo[2], mainInfo[1]), authCookie) # get course evals data
    courseData = []
    courseData.extend(mainInfo)
    courseData.extend(subInfo)
    courseData.extend(metrics)
    return courseData

def scrapeTermCourses(term, keyFields=DEFUALT_KEYFIELDS):
    '''
    Scrapes for the logistical information of all courses in a given term.
    IN
        term; term number to scrape courses from
        keyFields; names of the fields from which to collect course data values
    OUT
        list of lists of each course's data
    '''
    allCourseData = []
    # try/catch loop to protect against internet connection failure.
    # keep trying to access webpage until successful
    success = False
    while not success:
        try:
            courseUrls = scrapeCatalogue(term) # get the urls of all courses in this term
            success = True
        except:
            pass
    counter = 0
    for url in courseUrls:
        counter += 1
        print(counter)
        print(counter / len(courseUrls)) # report progress
        success = False
        # try/catch loop to protect against internet connection failure.
        # keep trying to access webpage until successful
        while not success:
            try:
                # collect the data at each url
                mainInfo, subInfo = scrapeCourse(url, keyFields)
                data = []
                data.extend(mainInfo)
                data.extend(subInfo)
                allCourseData.append(data)
                success = True
            except:
                pass

    return allCourseData



def writeCsv(fieldHeaders, courseData, filename):
    '''
    Writes course data to a csv file
    IN 
        fieldHeaders; list of strings representing the column headers in csv
        courseData; data to record in csv
        filename; string name (end in ".csv") of file to write to
    '''
    with open(filename, 'w') as csvfile:
        csvwriter = csv.writer(csvfile) 
        csvwriter.writerow(fieldHeaders) 
        csvwriter.writerows(courseData)
    




#urls, crns = getCatalogueData(term)


#url = "https://courses.rice.edu/courses/!SWKSCAT.cat?p_action=COURSE&p_term=202120&p_crn=20244"
#url = "https://courses.rice.edu/admweb/!SWKSCAT.cat?p_action=COURSE&p_term=201610&p_crn=14296"
#url = "https://courses.rice.edu/courses/!SWKSCAT.cat?p_action=COURSE&p_term=202130&p_crn=30877"


#courseInfo = scrapeCourse(url)
#print(courseInfo)

#authCookie = {'SESSID': 'R01MTElONTYwNTI1'}

# Scrape course data for all courses 2020 fall to 2021 spring
terms = [202110, 202120]
csvFilename = "2021 Course Information.csv"
fieldHeaders = ['title', 'crn', 'term']
keyFields = DEFUALT_KEYFIELDS
fieldHeaders.extend(keyFields)
courseData = []

for term in terms:
    courseData.append(scrapeTermCourses(term, keyFields))

print(courseData)

writeCsv(fieldHeaders, courseData, csvFilename)

print("____END____")
