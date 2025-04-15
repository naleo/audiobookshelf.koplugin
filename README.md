# Audiobookshelf for KOReader

This is a a KOReader plugin to allow you to browse and download books from an Audiobookshelf Server

## Installation

1. Unzip the release into your KOReader plugins directory
2. Copy the `audiobookshelf_config.example.lua` file to `audiobookshelf_config.lua`
3. Add your Audiobookshelf user's API key as `token` in the config file.  This can be found on your audiobookshelf server at Settings > Users > Click your username
4. Add the `server` to the config file, specifically the url of your server (no trailing slash)

## Usage

The Audiobookshelf Browser can be found in the tools menu. 

![FileManager_2025-04-14_164132](https://github.com/user-attachments/assets/99ccfb5c-67b7-47a9-bdd0-cca2ece99c4e)

Once open, you can view the list of libraries available to your Audiobookshelf user

![FileManager_2025-04-14_171731](https://github.com/user-attachments/assets/09d924c7-96d1-41d1-b68e-614da964cd63)

Click on one, and you will get the list of books available from that library (this only returns Audiobookshelf items that contain at least one eBook file)

![FileManager_2025-04-14_171903](https://github.com/user-attachments/assets/423a5c74-2578-4361-bc5a-acdfc3286ddf)

If you click on a book, you go to the Book Details page, which gives details about the book, including a list of Downloadable files:

![FileManager_2025-04-14_172035](https://github.com/user-attachments/assets/43c94cb7-28d1-4931-a658-8e321c528ea9)

Click on the name of one of the Downloadable files, and follow the process to download the eBook.

![FileManager_2025-04-14_172211](https://github.com/user-attachments/assets/a05ce960-48ae-4bf7-a5a3-54b161a3b211)
