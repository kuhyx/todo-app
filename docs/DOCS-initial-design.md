What:
toDo android and gnu/linux app

Why:
I get an influx of ideas every now and then, whether on my pc or on my mobile, I would like to write them down quickly and store them both on local device and on some remote server to use them later

Functional requirements:
1. Offline first, should work without internet at all
2. Sync between mobile and pc seamlessly and resolve merge conflicts (suggestion in technical)
3. Store those notes on remote private service (suggestion in technical)
4. The same experience on both mobile and pc
5. Option to export all notes to a single recoverable sync files

Using the app:
1. When opening app show an input text where you can immediately write down the idea and it gets saved character by character to local device (no interruptions, immediate), after user clicks "save" sync it with other devices running this app and with remote services
2. User can also open history of all available ideas with options to filter and sort them based on:
    a) when they were originally created
    b) when they were last modified
    c) alphabetically
    d) priority
3. Option to tier ideas based on their priority


Technical requirements:
1. Supports only markdown
2. Same codebase for mobile and pc
3. 100% test coverage
4. Hardest available lint tools for toolstack
5. For merge conflicts just use git ?
6. For remote private service use private github gits? In any way the app should be 100% compatible with this remote service, the service itself should be free for small text files we will be using and it should be private

The most important part: I do not want to lose those ideas thats why I want them to be stored in so many distributed places (locally, between my devices and on remote services)
