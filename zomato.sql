/******************************************************************
 STEP 0️⃣ : Create Database and Preview Data
******************************************************************/

-- Create database and use it
CREATE DATABASE zomatodb;
USE zomatodb;

-- Preview Restaurant Metadata
SELECT * 
FROM zomatodb.dbo.zomato_Restaurant_names_and_metadata;

-- Preview Reviews Data
SELECT * 
FROM zomatodb.dbo.Zomato_Restaurant_reviews_1;

-- Top 10 most expensive restaurants
SELECT TOP 10 Name, Cost
FROM zomatodb.dbo.zomato_Restaurant_names_and_metadata
ORDER BY Cost DESC;


/******************************************************************
 STEP 1️⃣ : Check Database Objects and Structure
******************************************************************/

-- List all tables
SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE';

-- Columns of all tables
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_CATALOG = 'zomatodb'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

-- Preview first 5 rows
SELECT TOP 5 * 
FROM zomatodb.dbo.zomato_Restaurant_names_and_metadata;

SELECT TOP 5 * 
FROM zomatodb.dbo.Zomato_Restaurant_reviews_1;


/******************************************************************
 STEP 2️⃣ : Check Null Values in Original Tables
******************************************************************/

-- Nulls in metadata table
SELECT COUNT(*) AS TotalRows,
       COUNT(DISTINCT Name) AS UniqueNames,
       COUNT(DISTINCT Cuisines) AS UniqueCuisines,
       COUNT(*) - COUNT(Name) AS NullNames,
       COUNT(*) - COUNT(Cuisines) AS NullCuisines
FROM zomatodb.dbo.zomato_Restaurant_names_and_metadata;

-- Nulls in reviews table
SELECT COUNT(*) AS TotalRows,
       COUNT(DISTINCT Review) AS UniqueReviews,
       COUNT(DISTINCT Rating) AS UniqueRatings,
       COUNT(*) - COUNT(Review) AS NullReviews,
       COUNT(*) - COUNT(Rating) AS NullRatings
FROM zomatodb.dbo.Zomato_Restaurant_reviews_1;


/******************************************************************
 STEP 3️⃣ : Trim and Standardize Text Columns
******************************************************************/

-- Convert Names to uppercase and trim spaces in Restaurants
UPDATE zomatodb.dbo.zomato_Restaurant_names_and_metadata
SET Name = UPPER(LTRIM(RTRIM(Name)));

-- Convert Restaurant names in Reviews to uppercase and trim spaces
UPDATE zomatodb.dbo.Zomato_Restaurant_reviews_1
SET Restaurant = UPPER(LTRIM(RTRIM(Restaurant)));

-- Check first 10 names after trimming & uppercase
SELECT TOP 10 Name
FROM zomatodb.dbo.zomato_Restaurant_names_and_metadata;


/******************************************************************
 STEP 4️⃣ : Create Cleaned Tables without Duplicates
******************************************************************/

-- Drop cleaned tables if they exist
DROP TABLE IF EXISTS Restaurants_Cleaned;
DROP TABLE IF EXISTS Reviews_Cleaned;

-- Cleaned Restaurants table
SELECT DISTINCT Name, Links, Cost, Collections, Cuisines, Timings
INTO Restaurants_Cleaned
FROM zomatodb.dbo.zomato_Restaurant_names_and_metadata;

SELECT TOP 10 *
FROM Restaurants_Cleaned;

-- Cleaned Reviews table
SELECT DISTINCT Restaurant, Reviewer, Review, Rating, Metadata, Time, Pictures
INTO Reviews_Cleaned
FROM zomatodb.dbo.Zomato_Restaurant_reviews_1;

SELECT TOP 10 *
FROM Reviews_Cleaned;


/******************************************************************
 STEP 5️⃣ : Add IDs and Map Reviews to Restaurants
******************************************************************/

-- Add RestaurantID in Restaurants
ALTER TABLE Restaurants_Cleaned
ADD RestaurantID INT IDENTITY(1,1) PRIMARY KEY;

-- Add RestaurantID in Reviews
ALTER TABLE Reviews_Cleaned
ADD RestaurantID INT;

-- Map Reviews to Restaurants using Restaurant Name
UPDATE rc
SET rc.RestaurantID = r.RestaurantID
FROM Reviews_Cleaned rc
JOIN Restaurants_Cleaned r
  ON rc.Restaurant = r.Name;

-- Verify mapping
SELECT COUNT(*) AS UnmappedReviews
FROM Reviews_Cleaned
WHERE RestaurantID IS NULL;  -- should return 0


/******************************************************************
 STEP 6️⃣ : Handle Missing Values
******************************************************************/

-- Missing Cuisines → 'Unknown'
UPDATE Restaurants_Cleaned
SET Cuisines = 'Unknown'
WHERE Cuisines IS NULL;

-- Missing Review text → 'No Review'
UPDATE Reviews_Cleaned
SET Review = 'No Review'
WHERE Review IS NULL;

-- Missing Rating → 0
UPDATE Reviews_Cleaned
SET Rating = 0
WHERE Rating IS NULL;


/******************************************************************
 STEP 7️⃣ : Categorize Restaurants by Cost
******************************************************************/

-- Add Cost_Category column
ALTER TABLE Restaurants_Cleaned
ADD Cost_Category NVARCHAR(20);

-- Fill Cost_Category
UPDATE Restaurants_Cleaned
SET Cost_Category = CASE
    WHEN TRY_CAST(Cost AS FLOAT) < 500 THEN 'Budget'
    WHEN TRY_CAST(Cost AS FLOAT) BETWEEN 500 AND 1000 THEN 'Mid'
    WHEN TRY_CAST(Cost AS FLOAT) > 1000 THEN 'Premium'
    ELSE 'Unknown'
END;

-- Verify first 10
SELECT TOP 10 Name, Cost, Cost_Category
FROM Restaurants_Cleaned;

-- Total restaurants per Cost_Category
SELECT Cost_Category, COUNT(*) AS TotalRestaurants
FROM Restaurants_Cleaned
GROUP BY Cost_Category;


/******************************************************************
 STEP 8️⃣ : Prepare Ratings Column
******************************************************************/

-- Convert Rating column to FLOAT
ALTER TABLE Reviews_Cleaned
ALTER COLUMN Rating FLOAT;

-- Replace invalid ratings with 0
UPDATE Reviews_Cleaned
SET Rating = 0
WHERE TRY_CAST(Rating AS FLOAT) IS NULL
  AND Rating IS NOT NULL;

-- Add ReviewID as primary key
ALTER TABLE Reviews_Cleaned
ADD ReviewID INT IDENTITY(1,1) PRIMARY KEY;

-- Check first 10 rows
SELECT TOP 10 *
FROM Reviews_Cleaned;


/******************************************************************
 STEP 9️⃣ : Advanced Analysis
******************************************************************/

-- Average rating & total reviews per restaurant
SELECT r.Name,
       AVG(v.Rating) AS AvgRating,
       COUNT(v.ReviewID) AS TotalReviews
FROM Restaurants_Cleaned r
JOIN Reviews_Cleaned v
  ON r.RestaurantID = v.RestaurantID
GROUP BY r.Name
ORDER BY AvgRating DESC;

-- Top 10 restaurants by number of reviews
SELECT TOP 10 r.Name,
       COUNT(v.ReviewID) AS TotalReviews
FROM Restaurants_Cleaned r
JOIN Reviews_Cleaned v
  ON r.RestaurantID = v.RestaurantID
GROUP BY r.Name
ORDER BY TotalReviews DESC;

-- Ranking restaurants by average rating (Window Function)
WITH RatingRank AS (
    SELECT r.Name,
           AVG(v.Rating) AS AvgRating,
           COUNT(v.ReviewID) AS TotalReviews,
           RANK() OVER (ORDER BY AVG(v.Rating) DESC) AS RatingRank
    FROM Restaurants_Cleaned r
    JOIN Reviews_Cleaned v
      ON r.RestaurantID = v.RestaurantID
    GROUP BY r.Name
)
SELECT *
FROM RatingRank
WHERE RatingRank <= 10;

-- Restaurants by Cost Category
SELECT r.Cost_Category,
       COUNT(r.RestaurantID) AS TotalRestaurants,
       AVG(TRY_CAST(r.Cost AS FLOAT)) AS AvgCost,
       AVG(v.Rating) AS AvgRating
FROM Restaurants_Cleaned r
LEFT JOIN Reviews_Cleaned v
  ON r.RestaurantID = v.RestaurantID
GROUP BY r.Cost_Category;
