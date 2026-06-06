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
        alert('Download feature coming soon! Sindri PDF DMG will be available here.');
    });
});
