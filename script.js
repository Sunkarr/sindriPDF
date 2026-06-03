document.addEventListener('DOMContentLoaded', () => {
    // Intersection Observer for scroll animations
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
            }
        });
    }, {
        threshold: 0.1
    });

    const hiddenElements = document.querySelectorAll('.fade-in');
    hiddenElements.forEach((el) => observer.observe(el));

    // Dummy interactions for buttons
    const downloadBtn = document.getElementById('download-btn');
    downloadBtn.addEventListener('click', (e) => {
        e.preventDefault();
        alert('Download feature coming soon! SimplePDF DMG will be available here.');
    });

    const coffeeBtns = document.querySelectorAll('.btn-small');
    coffeeBtns.forEach(btn => {
        if(btn.textContent.includes('coffee')) {
            btn.addEventListener('click', (e) => {
                e.preventDefault();
                alert('Thank you! Buy Me a Coffee integration coming soon.');
            });
        }
    });
});
